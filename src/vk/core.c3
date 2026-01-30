module vk;

import std::collections::elastic_array;
import std::math;
import app;
import window;
import constants;

const MAX_SHADER_CNT = 10u;

struct VulkanContext
{
	App*						app_ctx;
	FrameDataSOA				frame_data;
	VulkanDevice            	dev;
	VulkanSwapchain         	swapchain;
	VulkanRenderer				renderer;
	ElasticArray{VulkanShader, MAX_SHADER_CNT} shaders;
	VkInstance              	instance;
	VkSurfaceKHR            	surface;
	VkDebugUtilsMessengerEXT	debug_messenger;
	VkAllocationCallbacks*		vk_alloc;
	uint						curr_frame;
	uint						curr_shader;
}

struct FrameDataSOA
{
	ElasticArray{VulkanCmdPool, constants::FRAMES_IN_FLIGHT}  			cmd_pools;
	ElasticArray{VkCommandBuffer, constants::FRAMES_IN_FLIGHT} 			cmd_buffers;
	ElasticArray{VulkanCmdBufferState, constants::FRAMES_IN_FLIGHT} 	cmd_buffer_states;
	ElasticArray{VulkanSemaphore, constants::FRAMES_IN_FLIGHT}			image_avail_semaphores;
	ElasticArray{VulkanSemaphore, constants::FRAMES_IN_FLIGHT}			resource_transfer_end_semaphores;
	ElasticArray{VulkanSemaphore, constants::FRAMES_IN_FLIGHT}			render_end_semaphores;
	ElasticArray{VulkanFence, constants::FRAMES_IN_FLIGHT}    			render_end_fences;
}

struct FrameDataSOAView
{
	VulkanCmdPool[]   		cmd_pools;
	VkCommandBuffer 		cmd_buffers;
	VulkanCmdBufferState 	cmd_buffer_states;
	VkSemaphore[]     		image_avail_semaphores;
	VkSemaphore[]     		resource_transfer_end_semaphores;
	VkSemaphore[]     		render_end_semaphores;
	VkFence[]         		render_end_fences;
}

struct FrameData
{
	VulkanCmdPool        cmd_pool;
	VkCommandBuffer      cmd_buffer;
	VulkanCmdBufferState state;
	VkSemaphore          image_avail_semaphore;
	VkSemaphore          resource_transfer_end_semaphore;
	VkSemaphore          render_end_semaphore;
	VkFence              render_end_fence;
}

faultdef
	INSTANCE_INIT_FAILED,
	DEVICE_INIT_FAILED,
	SWAPCHAIN_INIT_FAILED;

fn void? init_vk(App* app_ctx, AppConfig* app_config, Window* window)
{
	vk_check(vk::volk_initialize());

	app_ctx.vk_ctx.app_ctx = app_ctx;
	VulkanContext* vk_ctx = &app_ctx.vk_ctx;

	if (!init_instance(vk_ctx, app_config)) {
		return INSTANCE_INIT_FAILED~;
	}

	window.create_vk_surface(vk_ctx.instance, &vk_ctx.surface);

	if (!init_device(vk_ctx)) {
		return DEVICE_INIT_FAILED~;
	}

	VkExtent2D extent = { app_config.init_width, app_config.init_height };
	if (!init_swapchain(vk_ctx, extent)) {
		return SWAPCHAIN_INIT_FAILED~;
	}

	vk_ctx.init_frame_data();

	vk_ctx.renderer.init(extent, constants::COLOR_BLACK_RGBA);

	create_main_shader(vk_ctx);
}

fn void VulkanContext.init_frame_data(&ctx) @private
{
	FrameDataSOA* frame_data = &ctx.frame_data;

	for (uint i = 0; i < constants::FRAMES_IN_FLIGHT; ++i) {
		VulkanCmdPool* pool = &frame_data.cmd_pools[i];
		pool.init(ctx, ctx.dev.queue_indices.graphics.fam);
		VulkanCmdBufferSOAView cmd_buffers_view = {
			.handles = { frame_data.cmd_buffers[i] },
			.states = { frame_data.cmd_buffer_states[i] },
		};
		pool.allocate_cmd_buffers(&ctx.dev, cmd_buffers_view, true);
	}
	foreach (&sem : frame_data.image_avail_semaphores) {
		sem.init(ctx);
	}
	foreach (&sem : frame_data.render_end_semaphores) {
		sem.init(ctx);
	}
	foreach (&sem : frame_data.resource_transfer_end_semaphores) {
		sem.init(ctx);
	}
	foreach (&fence : frame_data.render_end_fences) {
		fence.init(ctx);
	}
}

fn void create_main_shader(VulkanContext* ctx) @local
{
	const MAIN_SHADER_ATTRIB_CNT = 3u;
	const MAIN_SHADER_MAX_ENTITY_CNT = 1024u;
	const MAIN_SHADER_NAME = "shader_main.spv";

	ElasticArray{VkDescriptorSetLayoutBinding, 5}[2] descriptor_bindings;

	VkDescriptorType[*] global_descriptor_types = { VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER };
	VkDescriptorType[*] local_descriptor_types = {
		VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
		VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
		VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
		VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
		VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
	};

	descriptor_bindings[0].resize(global_descriptor_types.len);
	descriptor_bindings[1].resize(local_descriptor_types.len);

	// global ubo
	create_descriptor_bindings(
		VK_SHADER_STAGE_VERTEX_BIT,
		global_descriptor_types[..],
		descriptor_bindings[0].array_view(),
	);

	// local ubo
	create_descriptor_bindings(
		VK_SHADER_STAGE_FRAGMENT_BIT,
		local_descriptor_types[..],
		descriptor_bindings[1].array_view(),
	);

	VkDescriptorSetLayoutBinding[][2] bindings = { descriptor_bindings[0].array_view(), descriptor_bindings[1].array_view() };

	// attrib descriptions
    VkVertexInputAttributeDescription[MAIN_SHADER_ATTRIB_CNT] attrib_descriptions;
	
    // Position
    attrib_descriptions[0].binding = 0;
    attrib_descriptions[0].location = 0;
    attrib_descriptions[0].format = VK_FORMAT_R32G32B32_SFLOAT;
    attrib_descriptions[0].offset = 0;
    // Normal
    attrib_descriptions[1].binding = 0;
    attrib_descriptions[1].location = 1;
    attrib_descriptions[1].format = VK_FORMAT_R32G32B32_SFLOAT;
    attrib_descriptions[1].offset = math::SimdVec3.sizeof;
    // Texture sampler
    attrib_descriptions[2].binding = 0;
    attrib_descriptions[2].location = 2;
    attrib_descriptions[2].format = VK_FORMAT_R32G32_SFLOAT;
    attrib_descriptions[2].offset = math::SimdVec3.sizeof * 2;

    VkPushConstantRange[1] push_constant_ranges = {
		{
	        .stage_flags = VK_SHADER_STAGE_VERTEX_BIT,
	        .offset = 0,
	        .size = math::Mat4.sizeof,
		}
	};

	VulkanPipelineConfig[1] pipeline_configs = {
		{
			.primitive_topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
			.polygon_mode = VK_POLYGON_MODE_FILL,
			.line_width = 1.0f,
			.sample_count = VK_SAMPLE_COUNT_1_BIT ,
			.enable_color_blend = true,
		}
	};

	VulkanShaderConfig shader_conf = {
		.stage_bits = VulkanShaderStageKind.VERTEX | VulkanShaderStageKind.FRAGMENT,
		.descriptor_bindings = bindings[..],
		.attrib_descriptions = attrib_descriptions[..],
		.pipeline_configs = pipeline_configs[..],
		.push_constant_ranges = push_constant_ranges[..],
		.max_entities_per_frame = MAIN_SHADER_MAX_ENTITY_CNT,
		.vertex_binding_index = 0,
	};

	ctx.curr_shader = 0;
	ctx.shaders[0] = create_shader(ctx, MAIN_SHADER_NAME, &shader_conf);
}

fn void VulkanContext.destroy_frame_data(&ctx) @private
{
	FrameDataSOA* frame_data = &ctx.frame_data;

	for (uint i = 0; i < constants::FRAMES_IN_FLIGHT; ++i) {
		VulkanCmdPool* pool = &frame_data.cmd_pools[i];
		VulkanCmdBufferSOAView cmd_buffers_view = {
			.handles = { frame_data.cmd_buffers[i] },
			.states = { frame_data.cmd_buffer_states[i] },
		};
		pool.free_cmd_buffers(&ctx.dev, cmd_buffers_view);
		pool.destroy(ctx);
	}

	foreach (&sem : frame_data.image_avail_semaphores) {
		sem.destroy(ctx);
	}
	foreach (&sem : frame_data.render_end_semaphores) {
		sem.destroy(ctx);
	}
	foreach (&sem : frame_data.resource_transfer_end_semaphores) {
		sem.destroy(ctx);
	}
	foreach (&fence : frame_data.render_end_fences) {
		fence.destroy(ctx);
	}
}

fn void VulkanContext.destroy(&ctx)
{
	ctx.destroy_frame_data();
	ctx.swapchain.destroy(ctx);
	ctx.dev.destroy(ctx);
	vkDestroyInstance(ctx.instance, ctx.vk_alloc);
}
