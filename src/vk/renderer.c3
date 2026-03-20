module engine::vk;

import vk;
import logger;
import std::math;

struct VulkanRenderer
{
	GlobalMatrices                            global_matrices;
	VkDescriptorSet[engine::FRAMES_IN_FLIGHT] global_descriptor_sets;
	VulkanElementBuffer{ushort}               elem_buff;
	VkViewport                                viewport;
	VkRect2D                                  scissors;
	Camera                                    camera;
	DeltaClock                                frame_clock;
	VulkanDescriptorPool                      global_descriptor_pool;
	VulkanDescriptorSetLayout                 global_descriptor_layout;
	ColorRGBA                                 clear_color;
	bool                                      resize_scheduled;
	uint frame_counter                        @if($feature(SF_FRAME_COUNT));
}

struct GlobalMatrices
{
	Mat4 view;
	Mat4 proj;
}

fn void VulkanRenderer.init(
	&renderer,
	VulkanContext* ctx,
	VkExtent2D init_area,
	ColorRGBA init_clear_color = COLOR_BLACK_RGBA
)
{
	renderer.clear_color = init_clear_color;
	renderer.viewport = {
		.x = 0.0f,
		.y = 0.0f,
		.height = (float)init_area.height,
		// NOTE: should be configurable and passed to perspective()
		.width = (float)init_area.width,
		.minDepth = 0.0f,
		.maxDepth = 100.0f,
	};
	renderer.scissors = {
		.offset = engine::OFFSET_START,
		.extent = init_area,
	};

	init_elem_buffer{ushort}(
		&renderer.elem_buff,
		ctx,
		engine::get_cube_vertices()[..],
		engine::get_cube_indices(ushort)[..]
	)!!;

	renderer.camera.init({ 0, 0, 2 }, engine::V3_FAR);
	renderer.update_view_projection();

	initialize_event_handlers(&ctx.app_ctx.event_sys);

	$if $feature(SF_FRAME_COUNT):
		renderer.frame_counter = 0;
	$endif
}

fn void VulkanRenderer.start_clock(&renderer)
{
	renderer.frame_clock.start();
}

fn SwapchainPresentRes begin_frame(VulkanContext* ctx)
{
	ctx.swapchain.recreate_if_needed(ctx);
	return ctx.swapchain.acquire_next_image_index(
		ctx,
		0,
		ctx.frame_data[ctx.curr_frame].image_avail_sem.handle
	);
}

fn void draw_frame(VulkanContext* ctx)
{
	FrameData* frame = ctx.access_curr_frame_data();
	VulkanElementBuffer{ushort}* elem_buff = &ctx.renderer.elem_buff;
	VulkanShader* shader = ctx.access_curr_shader();
	VulkanPipeline* pipeline = shader.get_curr_pipeline();
	uint curr_frame = ctx.curr_frame;

	// --- Step: transfer resources
	frame.transfer_cmd_buff.begin_recording();

	if (ctx.renderer.resize_scheduled || ctx.renderer.camera.dirty)
	{
		// NOTE: (HACK) only start receiving move events when first resize happens
		// because it will have big mouse delta to go from init hardcoded window coords
		// to actual window coords
		// TODO: we may need to make it as event, if more things want to know when this happens
		if (!ctx.app_ctx.input_sys.accept_move_events)
		{
			ctx.app_ctx.input_sys.accept_move_events = true;
		}
		ctx.renderer.update_view_projection();
	}

	VkBufferCopy copy_region = {
		.srcOffset = 0,
		.dstOffset = 0,
		.size = elem_buff.all_size_bytes,
	};
	frame.transfer_cmd_buff.cmd_copy_data_between_buff(
		elem_buff.staging_buff,
		elem_buff.main_buff,
		&copy_region
	);
	frame.transfer_cmd_buff.end_recording();

	VkSubmitInfo transfer_submit_info = {
		.sType = vk::STRUCTURE_TYPE_SUBMIT_INFO,
		.commandBufferCount = 1,
		.pCommandBuffers = &frame.transfer_cmd_buff.handle,
		.signalSemaphoreCount = 1,
		.pSignalSemaphores = &frame.transfer_end_sem.handle,
	};

	frame.transfer_cmd_buff.submit(
		ctx,
		ctx.dev.transfer_queue,
		&transfer_submit_info,
		null
	);

	// --- Step: bind resources
	frame.graphics_cmd_buff.begin_recording();
	elem_buff.bind(frame.graphics_cmd_buff);
	pipeline.bind(frame.graphics_cmd_buff);
	ctx.renderer.bind_viewport_scissors(frame.graphics_cmd_buff);
	shader.bind_descriptor_sets(
		frame.graphics_cmd_buff,
		vk::PIPELINE_BIND_POINT_GRAPHICS,
		(&ctx.renderer.global_descriptor_sets[curr_frame])[:1]
	);

	// --- Step: draw into the render target
	begin_rendering(ctx, &frame.graphics_cmd_buff);
	// ctx.renderer.update_proj(curr_frame, ctx.renderer.calc_proj_mat_from_aspect());
	Mat4 model = matrix::IDENTITY4;
	model = model.scale({ 0.4f, 0.4f, 0.4f });
	// model = model.translate({ 0.0f, 2.0f, 0.0f });
	frame.graphics_cmd_buff.cmd_push_mvp(
		pipeline,
		model,
		ctx.renderer.global_matrices.view,
		ctx.renderer.global_matrices.proj
	);

	// NOTE: TEMP geometry view
	GeometryView temp_view = elem_buff.get_full_geometry_view();
	// NOTE: draw call
	frame.graphics_cmd_buff.cmd_draw_geometry(temp_view);

	end_rendering(ctx, &frame.graphics_cmd_buff);
	frame.graphics_cmd_buff.end_recording();

	// --- Step submit graphics buffer
	const WAIT_SEM_COUNT = 2;
	VkSemaphore[WAIT_SEM_COUNT] wait_semaphores = {
		frame.image_avail_sem.handle,
		frame.transfer_end_sem.handle
	};
	VkPipelineStageFlags[WAIT_SEM_COUNT] wait_dest_mask = {
		vk::PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
		vk::PIPELINE_STAGE_VERTEX_INPUT_BIT
	};

	VkSubmitInfo submit_info = {
		.sType = vk::STRUCTURE_TYPE_SUBMIT_INFO,
		.waitSemaphoreCount = WAIT_SEM_COUNT,
		.pWaitSemaphores = &wait_semaphores,
		.pWaitDstStageMask = &wait_dest_mask,
		.commandBufferCount = 1,
		.pCommandBuffers = &frame.graphics_cmd_buff.handle,
		.signalSemaphoreCount = 1,
		.pSignalSemaphores = &frame.render_end_sem.handle,
	};

	frame.graphics_cmd_buff.submit(
		ctx,
		ctx.dev.graphics_queue,
		&submit_info,
		&frame.render_end_fence
	);
	ctx.swapchain.present(
		ctx,
		ctx.dev.present_queue,
		frame.render_end_sem.handle
	);

	$if ($feature (SF_FRAME_COUNT)):
		logger::logn(INFO, "frame count: %d", ctx.renderer.frame_counter++);
	$endif
}

fn void end_frame(VulkanContext* ctx)
{
	FrameData* frame = ctx.access_curr_frame_data();
	frame.render_end_fence.wait(ctx)!!;
	frame.render_end_fence.reset(ctx);
	frame.transfer_cmd_buff.reset();
	frame.graphics_cmd_buff.reset();
	ctx.renderer.frame_clock.update();
	ctx.app_ctx.input_sys.update();
	ctx.advance_frame();
}

fn void VulkanRenderer.set_clear_color(
	&renderer,
	ColorRGBA clear_color = COLOR_BLACK_RGBA
) @inline
{
	renderer.clear_color = clear_color;
}

fn void VulkanRenderer.update_viewport_scissors(&renderer, VkExtent2D area)
{
	renderer.viewport = {
		.width = (float)area.width,
		.height = (float)area.height,
	};
	renderer.scissors.extent = area;
}

fn void VulkanRenderer.cmd_send_viewport_scissors(
	&renderer,
	VulkanCmdBuffer cmd_buffer
)
{
	vk::cmdSetViewport(cmd_buffer.handle, 0, 1, &renderer.viewport);
	vk::cmdSetScissor(cmd_buffer.handle, 0, 1, &renderer.scissors);
}

fn void VulkanRenderer.bind_viewport_scissors(
	&renderer,
	VulkanCmdBuffer graphics_cmd_buffer
)
{
	vk::cmdSetViewport(graphics_cmd_buffer.handle, 0, 1, &renderer.viewport);
	vk::cmdSetScissor(graphics_cmd_buffer.handle, 0, 1, &renderer.scissors);
}

fn VkExtent2D VulkanRenderer.get_extent(&renderer) @inline
{
	return renderer.scissors.extent;
}

fn float VulkanRenderer.aspect_ratio(&renderer) @inline
{
	VkExtent2D extent = renderer.get_extent();
	return (float)extent.width / extent.height;
}

<*
 @require cmd_buffer.state == VulkanCmdBufferState.RECORDING_BEGIN : "Should be in RECORDING_BEGIN state before 'begin_rendering'"
*>
fn void begin_rendering(VulkanContext* ctx, VulkanCmdBuffer* cmd_buffer)
{
	VulkanSwapchain* swapchain = &ctx.swapchain;
	VkImage curr_image = swapchain.access_curr_image();
	VkImageView curr_view = swapchain.access_curr_view();

	cmd_transition_layout_raw(
		curr_image,
		*cmd_buffer,
		vk::IMAGE_LAYOUT_UNDEFINED,
		vk::IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
		vk::PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		vk::PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
		0,
		vk::ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
		false
	);

	cmd_transition_layout_raw(
		ctx.swapchain.depth_image.handle,
		*cmd_buffer,
		vk::IMAGE_LAYOUT_UNDEFINED,
		vk::IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		vk::PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		vk::PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
		0,
		vk::ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT
			| vk::ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
		true
	);

	VkRenderingAttachmentInfo color_attachment_info = {
		.sType = vk::STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
		.imageView = curr_view,
		.imageLayout = vk::IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
		.loadOp = vk::ATTACHMENT_LOAD_OP_CLEAR,
		.storeOp = vk::ATTACHMENT_STORE_OP_STORE,
		.clearValue = {
			.color = { .float32 = ctx.renderer.clear_color },
			.depthStencil = { }
		},
	};

	VkRenderingAttachmentInfo depth_attachment_info = {
		.sType = vk::STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
		.imageView = ctx.swapchain.depth_image.view,
		.imageLayout = vk::IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
		.loadOp = vk::ATTACHMENT_LOAD_OP_CLEAR,
		.storeOp = vk::ATTACHMENT_STORE_OP_DONT_CARE,
		.clearValue = { .depthStencil = engine::CLEAR_DEPTH_VALUE },
	};

	VkRenderingInfo rendering_info = {
		.sType = vk::STRUCTURE_TYPE_RENDERING_INFO,
		.renderArea = {
			.offset = engine::OFFSET_START,
			.extent = ctx.renderer.scissors.extent
		},
		.layerCount = 1,
		.colorAttachmentCount = 1,
		.pColorAttachments = &color_attachment_info,
		.pDepthAttachment = &depth_attachment_info,
	};

	cmd_buffer.cmd_begin_rendering(&rendering_info);
}

fn void end_rendering(VulkanContext* ctx, VulkanCmdBuffer* cmd_buffer)
{
	cmd_buffer.cmd_end_rendering();
	VulkanSwapchain* swapchain = &ctx.swapchain;

	cmd_transition_layout_raw(
		swapchain.access_curr_image(),
		*cmd_buffer,
		vk::IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
		vk::IMAGE_LAYOUT_PRESENT_SRC_KHR,
		vk::PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		vk::PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
		0,
		vk::ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
		false
	);

	cmd_transition_layout_raw(
		swapchain.depth_image.handle,
		*cmd_buffer,
		vk::IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
		vk::IMAGE_LAYOUT_PRESENT_SRC_KHR,
		vk::PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		vk::PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
		0,
		vk::ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT
			| vk::ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
		true
	);
}

// --- Global descriptors (view & projection matrices)

<*
 @require renderer.resize_scheduled || renderer.camera.dirty : "One of these conditions should be true"
*>
fn void VulkanRenderer.update_view_projection(&renderer)
{
	renderer.global_matrices.view = renderer.camera.look_at();
	renderer.global_matrices.proj = matrix::perspective{float}(
		math::deg_to_rad(renderer.camera.zoom),
		renderer.aspect_ratio(),
		0.1f,
		100.0f
	);
	renderer.resize_scheduled = false;
	renderer.camera.dirty = false;
}

fn void VulkanCmdBuffer.cmd_push_mvp(
	&cmd_buffer,
	VulkanPipeline* pipeline,
	Mat4 model,
	Mat4 view,
	Mat4 proj
)
{
	Mat4 mvp = proj * view * model;
	vk::cmdPushConstants(
		cmd_buffer.handle,
		pipeline.layout,
		vk::SHADER_STAGE_VERTEX_BIT,
		0,
		Mat4.sizeof,
		&mvp
	);
}

// For calling from external modules
fn void VulkanRenderer.set_view_projection(&renderer, Mat4 view, Mat4 proj)
{
	renderer.global_matrices.view = view;
	renderer.global_matrices.proj = proj;
}

// For calling from external modules
fn void VulkanRenderer.set_view(&renderer, Mat4 view)
{
	renderer.global_matrices.view = view;
}

// For calling from external modules
fn void VulkanRenderer.set_proj(&renderer, Mat4 proj)
{
	renderer.global_matrices.proj = proj;
}

// --- Event handlers

fn void initialize_event_handlers(EventSystem* ev_sys) @local
{
	ev_sys.add_event_handler(MOUSE_MOVE, &handle_mouse_move);
	ev_sys.add_event_handler(KEY_DOWN, &handle_key_down);
	ev_sys.add_event_handler(MOUSE_WHEEL, &handle_mouse_wheel);
}

fn bool handle_mouse_move(EventContext ctx, void* listener) @local
{
	VulkanRenderer* renderer = (VulkanRenderer*)listener;
	float delta_x = ctx.f32[0];
	float delta_y = ctx.f32[1];
	renderer.camera.handle_mouse_move(delta_x, delta_y);
	return false;
}

fn bool handle_key_down(EventContext ctx, void* listener) @local
{
	VulkanRenderer* renderer = (VulkanRenderer*)listener;
	uint key = ctx.u32[0];
	double frame_delta_time_sec = renderer.frame_clock.get_delta_time_sec();
	renderer.camera.handle_key_down(key, frame_delta_time_sec);
	return false;
}

fn bool handle_mouse_wheel(EventContext ctx, void* listener) @local
{
	VulkanRenderer* renderer = (VulkanRenderer*)listener;
	bool delta = ctx.b8[0];
	renderer.camera.handle_mouse_wheel(delta);
	return false;
}
