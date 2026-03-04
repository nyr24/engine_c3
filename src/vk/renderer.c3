module vk;

import engine;
import logger;
import std::math;
import std::collections::elastic_array;

struct VulkanRenderer
{
	ElasticArray{VulkanGlobalUBO, engine::FRAMES_IN_FLIGHT}	global_ubos;
	ElasticArray{VkDescriptorSet, engine::FRAMES_IN_FLIGHT}	global_descriptor_sets;
	VulkanElementBuffer{ushort} 	elem_buff;
	ColorRGBA                       clear_color;
	VkViewport                      viewport;
	VkRect2D	                    scissors;
	double 			                delta_time;
	VulkanDescriptorPool			global_descriptor_pool;
	VulkanDescriptorSetLayout		global_descriptor_layout;

	// TODO:
	// Camera			camera;
}

fn void VulkanRenderer.init(&renderer, VulkanContext* ctx, VkExtent2D init_area, ColorRGBA init_clear_color = COLOR_BLACK_RGBA)
{
	renderer.clear_color = init_clear_color;
    renderer.viewport = {
        .x = 0.0f,
        .y = 0.0f,
        .width = (float)init_area.width,
        .height = (float)init_area.height,
        .min_depth = 0.0f,
        .max_depth = 1.0f,
    };
	renderer.scissors = {
		.offset = engine::OFFSET_START,
		.extent = init_area,
	};

	foreach (&ubo : renderer.global_ubos) {
		ubo.init(ctx)!!;
	}

	init_elem_buffer{ushort}(&renderer.elem_buff, ctx, engine::get_cube_vertices()[..], engine::get_cube_indices(ushort)[..])!!;
	init_global_descriptors(renderer, ctx);
}

fn void begin_frame(VulkanContext* ctx)
{
	vkQueueWaitIdle(ctx.dev.present_queue);
	ctx.swapchain.acquire_next_image_index(ctx, 0, ctx.frame_data[ctx.curr_frame].image_avail_sem.handle);
}

fn void draw_frame(VulkanContext* ctx)
{
	FrameData* frame = ctx.access_curr_frame_data();
	VulkanElementBuffer{ushort}* elem_buff = &ctx.renderer.elem_buff;
	VulkanShader* shader = ctx.access_curr_shader();
	uint curr_frame = ctx.curr_frame;

// --- Step: bind objects + transfer resources (vertices + indices)
    frame.transfer_cmd_buff.begin_recording();
	elem_buff.bind(frame.transfer_cmd_buff);
	shader.bind_curr_pipeline(frame.graphics_cmd_buff);
	shader.bind_descriptor_sets(
		frame.graphics_cmd_buff, VK_PIPELINE_BIND_POINT_GRAPHICS,
		(&ctx.renderer.global_descriptor_sets[curr_frame])[:1]
	);

    VkBufferCopy vertex_copy_region = {
        .src_offset = 0,
        .dst_offset = 0,
        .size = elem_buff.vertices_size_bytes,
    };

    VkBufferCopy index_copy_region = {
        .src_offset = elem_buff.vertices_size_bytes,
        .dst_offset = elem_buff.vertices_size_bytes,
        .size = elem_buff.indices_size_bytes(),
    };

    frame.transfer_cmd_buff.cmd_copy_data_between_buff(elem_buff.staging_buff, elem_buff.main_buff, &vertex_copy_region);
    frame.transfer_cmd_buff.cmd_copy_data_between_buff(elem_buff.staging_buff, elem_buff.main_buff, &index_copy_region);
    frame.transfer_cmd_buff.end_recording();

    VkSubmitInfo transfer_submit_info = {
        .s_type = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .command_buffer_count = 1,
        .p_command_buffers = &frame.transfer_cmd_buff.handle,
		.signal_semaphore_count = 1,
		.p_signal_semaphores = &frame.transfer_cmd_buff.handle,
    };

    frame.transfer_cmd_buff.submit(ctx, ctx.dev.transfer_queue, &transfer_submit_info, null);

// --- Step: draw into the render target

// NOTE: TEMP geometry view
	GeometryView temp_view = elem_buff.get_full_geometry_view();
	frame.graphics_cmd_buff.begin_recording();

	begin_rendering(ctx, &frame.graphics_cmd_buff);
// NOTE: draw call
	frame.graphics_cmd_buff.cmd_draw_geometry(temp_view);
	end_rendering(ctx, &frame.graphics_cmd_buff);

	frame.graphics_cmd_buff.end_recording();

// --- Step submit graphics buffer
	const WAIT_SEM_COUNT = 2;
	VkSemaphore[WAIT_SEM_COUNT] wait_semaphores = { frame.image_avail_sem.handle, frame.resource_transfer_end_sem.handle };
    VkPipelineStageFlags[WAIT_SEM_COUNT] wait_dest_mask = { VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT };

    VkSubmitInfo submit_info = {
        .s_type = VK_STRUCTURE_TYPE_SUBMIT_INFO,
	// NOTE: waiting on different semaphore (TEST)
        .wait_semaphore_count = WAIT_SEM_COUNT,
        .p_wait_semaphores = &wait_semaphores,
        .p_wait_dst_stage_mask = &wait_dest_mask,
        .command_buffer_count = 1,
        .p_command_buffers = &frame.graphics_cmd_buff.handle,
        .signal_semaphore_count = 1,
        .p_signal_semaphores = &frame.render_end_sem.handle,
    };

    frame.graphics_cmd_buff.submit(ctx, ctx.dev.present_queue, &submit_info, &frame.render_end_fence);
	SwapchainPresentRes res = ctx.swapchain.present(ctx, ctx.dev.present_queue, frame.render_end_sem.handle);
	logger::logn(INFO, "presentation result: %s", res);
}

fn void end_frame(VulkanContext* ctx)
{
	FrameData* frame = ctx.access_curr_frame_data();
	frame.render_end_fence.wait(ctx);
	frame.transfer_cmd_buff.reset();
	frame.graphics_cmd_buff.reset();
	ctx.advance_frame();
}

fn void VulkanRenderer.set_clear_color(&renderer, ColorRGBA clear_color = COLOR_BLACK_RGBA) @inline
{
	renderer.clear_color = clear_color;
}

fn void VulkanRenderer.set_viewport_scissors(&renderer, VkExtent2D area, VulkanCmdBuffer* cmd_buffer)
{
    renderer.viewport = {
        .width = (float)area.width,
        .height = (float)area.height,
    };
	renderer.scissors.extent = area;
    vkCmdSetViewport(cmd_buffer.handle, 0, 1, &renderer.viewport);
    vkCmdSetScissor(cmd_buffer.handle, 0, 1, &renderer.scissors);
}

fn void VulkanRenderer.bind_viewport_scissors(&renderer, VkCommandBuffer graphics_cmd_buffer)
{
    vkCmdSetViewport(graphics_cmd_buffer, 0, 1, &renderer.viewport);
    vkCmdSetScissor(graphics_cmd_buffer, 0, 1, &renderer.scissors);
}

fn void begin_rendering(VulkanContext* ctx, VulkanCmdBuffer* cmd_buffer)
{
	if (cmd_buffer.state != VulkanCmdBufferState.RECORDING_BEGIN) {
		cmd_buffer.begin_recording(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT);
	}
	
	VulkanSwapchain* swapchain = &ctx.swapchain;

    cmd_transition_layout_raw(
        swapchain.images[swapchain.curr_image],
        cmd_buffer,
        VK_IMAGE_LAYOUT_UNDEFINED,
        VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        0,
        VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
        false
    );

    cmd_transition_layout_raw(
        ctx.swapchain.depth_image.handle,
        cmd_buffer,
        VK_IMAGE_LAYOUT_UNDEFINED,
        VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
        0,
        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        true
    );

    VkRenderingAttachmentInfo color_attachment_info = {
        .s_type = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .image_view = swapchain.image_views[swapchain.curr_image],
        .image_layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .load_op = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .store_op = VK_ATTACHMENT_STORE_OP_STORE,
        .clear_value = { .color = { .float_32 = ctx.renderer.clear_color }, .depth_stencil = {} },
    };

    VkRenderingAttachmentInfo depth_attachment_info = {
        .s_type = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .image_view = ctx.swapchain.depth_image.view,
        .image_layout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .load_op = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .store_op = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clear_value = engine::CLEAR_DEPTH_VALUE,
    };

    VkRenderingInfo rendering_info = {
        .s_type = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .render_area = { .offset = engine::OFFSET_START, .extent = ctx.renderer.scissors.extent },
        .layer_count = 1,
        .color_attachment_count = 1,
        .p_color_attachments = &color_attachment_info,
        .p_depth_attachment = &depth_attachment_info,
    };

	cmd_buffer.cmd_begin_rendering(&rendering_info);
}

fn void end_rendering(VulkanContext* ctx, VulkanCmdBuffer* cmd_buffer)
{
    cmd_buffer.cmd_end_rendering();
	VulkanSwapchain* swapchain = &ctx.swapchain;

    cmd_transition_layout_raw(
        swapchain.images[swapchain.curr_image],
        cmd_buffer.handle,
        VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        0,
        VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
        false
    );

    cmd_transition_layout_raw(
        swapchain.depth_image.handle,
        cmd_buffer.handle,
        VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
        0,
        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        true
    );
}

// --- Global descriptors (view & projection matrices)

fn void VulkanRenderer.update_view_projection(
	&renderer,
	VulkanDevice* dev,
	uint curr_frame,
	Mat4 view,
	Mat4 proj
)
{
	renderer.global_ubos[curr_frame].update(view, proj);
	update_global_descriptors(renderer, dev, curr_frame);
}

fn void VulkanRenderer.update_view(&renderer, uint curr_frame, Mat4 view)
{
	renderer.global_ubos[curr_frame].update_view(view);
}

fn void VulkanRenderer.update_proj(&renderer, uint curr_frame, Mat4 proj)
{
	renderer.global_ubos[curr_frame].update_proj(proj);
}

fn void init_global_descriptors(VulkanRenderer* renderer, VulkanContext* ctx) @local
{
	renderer.global_descriptor_sets.resize_to_cap();
    VkDescriptorPoolSize[*] pool_sizes = {{ .type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptor_count = engine::FRAMES_IN_FLIGHT }};
    renderer.global_descriptor_pool.init(ctx, pool_sizes[..], engine::FRAMES_IN_FLIGHT);

    VkDescriptorType[*] types = { VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER };
    VkDescriptorSetLayoutBinding[types.len] bindings;
    create_descriptor_bindings(VK_SHADER_STAGE_VERTEX_BIT, types[..], bindings[..]);
    renderer.global_descriptor_layout.init(ctx, bindings[..]);

    ElasticArray{VulkanDescriptorSetLayout, engine::FRAMES_IN_FLIGHT} layouts;
	layouts.resize_to_cap();
    layouts.fill(renderer.global_descriptor_layout);

    renderer.global_descriptor_pool.allocate_sets(
		&ctx.dev, layouts.array_view(), renderer.global_descriptor_sets.array_view(),
	);

    update_global_descriptors(renderer, &ctx.dev, ctx.curr_frame);
}

fn void update_global_descriptors(VulkanRenderer* renderer, VulkanDevice* dev, uint curr_frame) @local
{
	VkDescriptorBufferInfo buffer_info = {
	    .buffer = renderer.global_ubos[curr_frame].buffer.handle,
	    .offset = 0,
	    .range = VulkanGlobalUBO.sizeof
	};
	VkWriteDescriptorSet descriptor_write = {
	    .s_type = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
	    .dst_set = renderer.global_descriptor_sets[curr_frame],
	    .dst_binding = 0,
	    .dst_array_element = 0,
	    .descriptor_count = 1,
	    .descriptor_type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
	    .p_image_info = null,
	    .p_buffer_info = &buffer_info,
	    .p_texel_buffer_view = null,
	};
	vkUpdateDescriptorSets(dev.log_dev, 1, &descriptor_write, 0, null);
}
