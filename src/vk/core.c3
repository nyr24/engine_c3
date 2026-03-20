module engine::vk;

import vk;
import window;
import logger;
import std::collections::elastic_array;
import std::math;

const MAX_SHADER_CNT = 10u;

struct VulkanContext
{
	FrameData[engine::FRAMES_IN_FLIGHT] frame_data;
	VulkanDevice            	dev;
	VulkanSwapchain         	swapchain;
	VulkanRenderer				renderer;
	ElasticArray{VulkanShader, MAX_SHADER_CNT} shaders;
	VkDebugUtilsMessengerEXT	debug_messenger;
	VkAllocationCallbacks*		vk_alloc;
	uint						curr_frame;
	uint						curr_shader;
	VulkanCmdPool  			    graphics_cmd_pool;
	VulkanCmdPool  			    transfer_cmd_pool;
	VkInstance              	instance;
	VkSurfaceKHR            	surface;
	App*						app_ctx;
}

struct FrameData
{
	VulkanCmdBuffer 	      graphics_cmd_buff;
	VulkanCmdBuffer 	      transfer_cmd_buff;
	VulkanSemaphore			  image_avail_sem;
	VulkanSemaphore			  transfer_end_sem;
	VulkanSemaphore			  render_end_sem;
// NOTE: PERF: 1 bool creates 7 bit padding in every instance
// SOLUTION: store cmd_buff states (2 chars) + fence.is_signaled here, at the end
// (BUT): we only have two of them...
	VulkanFence    			  render_end_fence;
}

faultdef
	INSTANCE_INIT_FAILED,
	DEVICE_INIT_FAILED,
	SWAPCHAIN_INIT_FAILED;

fn void? init_vk(App* app_ctx, AppConfig* app_config, Window* window)
{
	vk_check(vk::volkInitialize());

	app_ctx.vk_ctx.app_ctx = app_ctx;
	VulkanContext* ctx = &app_ctx.vk_ctx;

	if (!init_instance(ctx, app_config)) {
		return INSTANCE_INIT_FAILED~;
	}

	window.create_vk_surface(ctx.instance, &ctx.surface);

	if (!init_device(ctx)) {
		return DEVICE_INIT_FAILED~;
	}

	init_frame_data(ctx);

	VkExtent2D extent = { app_config.init_width, app_config.init_height };
	ctx.swapchain.init(ctx, extent)!;
	ctx.renderer.init(ctx, extent, engine::COLOR_DARK_BLUE_RGBA);
	create_main_shader(ctx);
}

fn VulkanShader* VulkanContext.access_curr_shader(&ctx)
{
	return &ctx.shaders[ctx.curr_shader];
}

fn FrameData* VulkanContext.access_curr_frame_data(&ctx)
{
	return &ctx.frame_data[ctx.curr_frame];
}

fn void VulkanContext.advance_frame(&ctx)
{
	ctx.curr_frame = ctx.curr_frame >= (engine::FRAMES_IN_FLIGHT - 1) ? 0 : ctx.curr_frame + 1;
}

fn void create_main_shader(VulkanContext* ctx) @local
{
	const MAIN_SHADER_MAX_ENTITY_CNT = 1024;
	const MAIN_SHADER_NAME = "shader_main.spv";

	// VkDescriptorSetLayoutBinding[1] descriptor_bindings;
	// VkDescriptorType[1] global_descriptor_types = { vk::DESCRIPTOR_TYPE_UNIFORM_BUFFER };
	// VkDescriptorType[*] local_descriptor_types = {
		// vk::DESCRIPTOR_TYPE_UNIFORM_BUFFER,
		// vk::DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
		// vk::DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
		// vk::DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
		// vk::DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
	// };

	// descriptor_bindings[0].resize(global_descriptor_types.len);
	// descriptor_bindings[1].resize(local_descriptor_types.len);

	// global ubo
	// create_descriptor_bindings(
	// 	vk::SHADER_STAGE_VERTEX_BIT,
	// 	global_descriptor_types[..],
	// 	descriptor_bindings[..],
	// );

	// local ubo
	// create_descriptor_bindings(
	// 	vk::SHADER_STAGE_FRAGMENT_BIT,
	// 	local_descriptor_types[..],
	// 	descriptor_bindings[1].array_view(),
	// );

	// VkDescriptorSetLayoutBinding[][1] shader_bindings = { descriptor_bindings[..] };

	// attrib descriptions
    VkVertexInputAttributeDescription[*] attrib_descriptions = {
	    // Position
		{
		    .binding = 0,
		    .location = 0,
		    .format = vk::FORMAT_R32G32B32_SFLOAT,
		    .offset = 0,
		},
	    // Normal
		{
		    .binding = 0,
		    .location = 1,
		    .format = vk::FORMAT_R32G32B32_SFLOAT,
		    .offset = Vec3.sizeof * 1,
		},
	    // Texture sampler
	    {
		    .binding = 0,
		    .location = 2,
		    .format = vk::FORMAT_R32G32_SFLOAT,
		    .offset = Vec3.sizeof * 2,
		},
		// NOTE: TEMP (color)
		{
		    .binding = 0,
		    .location = 3,
		    .format = vk::FORMAT_R32G32B32_SFLOAT,
		    .offset = Vec3.sizeof * 2 + Vec2.sizeof,
		}
	};

    VkPushConstantRange[1] push_constant_ranges = {
		{
	        .stageFlags = vk::SHADER_STAGE_VERTEX_BIT,
	        .offset = 0,
	        .size = math::Mat4.sizeof,
		}
	};

	VulkanPipelineConfig[1] pipeline_configs = {
		{
			.primitive_topology = vk::PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
			.polygon_mode = vk::POLYGON_MODE_FILL,
			.line_width = 1.0f,
			.sample_count = vk::SAMPLE_COUNT_1_BIT,
			.enable_color_blend = true,
		}
	};

	VulkanShaderConfig shader_conf = {
		.stage_bits = VulkanShaderStageKind.VERTEX | VulkanShaderStageKind.FRAGMENT,
		.descriptor_bindings = {},
		.attrib_descriptions = attrib_descriptions[..],
		.pipeline_configs = pipeline_configs[..],
		.push_constant_ranges = push_constant_ranges[..],
		.max_entities_per_frame = MAIN_SHADER_MAX_ENTITY_CNT,
		.vertex_binding_index = 0,
	};

	ctx.curr_shader = 0;
	ctx.shaders[0] = create_shader(ctx, MAIN_SHADER_NAME, &shader_conf);
}

<*
	Requires VulkanDevice to be initialized
*>
fn void init_frame_data(VulkanContext* ctx) @local
{
	if (!ctx.dev.graphics_matches_transfer_queue()) {
		logger::logn(INFO, "Graphics and Transfer queues are different");

		ctx.graphics_cmd_pool.init(ctx, ctx.dev.queue_indices.graphics.fam);
		ctx.transfer_cmd_pool.init(ctx, ctx.dev.queue_indices.transfer.fam);

		VkCommandBuffer[engine::FRAMES_IN_FLIGHT] graphics_buffs;
		VkCommandBuffer[engine::FRAMES_IN_FLIGHT] transfer_buffs;

		ctx.graphics_cmd_pool.allocate_cmd_buffers(&ctx.dev, graphics_buffs[..]);
		ctx.transfer_cmd_pool.allocate_cmd_buffers(&ctx.dev, transfer_buffs[..]);

		foreach (uint i, &frame : ctx.frame_data) {
			frame.graphics_cmd_buff.init(graphics_buffs[i]);
			frame.transfer_cmd_buff.init(transfer_buffs[i]);
		}
	} else {
		logger::logn(INFO, "Graphics and Transfer queues are the same");

		ctx.graphics_cmd_pool.init(ctx, ctx.dev.queue_indices.graphics.fam);
		VkCommandBuffer[engine::FRAMES_IN_FLIGHT * 2] cmd_buffs;
		ctx.graphics_cmd_pool.allocate_cmd_buffers(&ctx.dev, cmd_buffs[..]);

		uint i = 0;
		foreach (&frame : ctx.frame_data) {
			frame.graphics_cmd_buff.init(cmd_buffs[i++]);
			frame.transfer_cmd_buff.init(cmd_buffs[i++]);
		}
	}

	foreach (&data : ctx.frame_data) {
		data.image_avail_sem.init(ctx);
		data.transfer_end_sem.init(ctx);
		data.render_end_sem.init(ctx);
		data.render_end_fence.init(ctx);
	}
}

fn void destroy_frame_data(VulkanContext* ctx) @local
{
	if (!ctx.dev.graphics_matches_transfer_queue()) {
		VkCommandBuffer[engine::FRAMES_IN_FLIGHT] graphics_buffs;
		VkCommandBuffer[engine::FRAMES_IN_FLIGHT] transfer_buffs;

		foreach (uint i, &frame : ctx.frame_data) {
			graphics_buffs[i] = frame.graphics_cmd_buff.handle;
			transfer_buffs[i] = frame.transfer_cmd_buff.handle;
		}

		ctx.graphics_cmd_pool.free_cmd_buffers(&ctx.dev, graphics_buffs[..]);
		ctx.graphics_cmd_pool.destroy(ctx);
		ctx.transfer_cmd_pool.free_cmd_buffers(&ctx.dev, transfer_buffs[..]);
		ctx.transfer_cmd_pool.destroy(ctx);
	} else {
		VkCommandBuffer[engine::FRAMES_IN_FLIGHT * 2] cmd_buffs;
		uint i;
		foreach (&frame : ctx.frame_data) {
			cmd_buffs[i++] = frame.graphics_cmd_buff.handle;
			cmd_buffs[i++] = frame.transfer_cmd_buff.handle;
		}
		ctx.graphics_cmd_pool.free_cmd_buffers(&ctx.dev, cmd_buffs[..]);
		ctx.graphics_cmd_pool.destroy(ctx);
	}

	foreach (&data : ctx.frame_data) {
		data.graphics_cmd_buff.state = NOT_ALLOCATED;
		data.transfer_cmd_buff.state = NOT_ALLOCATED;
		data.image_avail_sem.destroy(ctx);
		data.render_end_sem.destroy(ctx);
		data.transfer_end_sem.destroy(ctx);
		data.render_end_fence.destroy(ctx);
	}
}

fn void VulkanContext.destroy(&ctx)
{
	foreach (&shader : ctx.shaders) {
		shader.destroy(ctx);
	}
	destroy_frame_data(ctx);
	ctx.swapchain.destroy(ctx);
	ctx.dev.destroy(ctx);
	vk::destroyInstance(ctx.instance, ctx.vk_alloc);
}

// Utility

fn bool VkExtent2D.eq(VkExtent2D first, VkExtent2D second) @operator(==)
{
	return first.width == second.width && first.height == second.height;
}
