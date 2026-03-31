module engine::vk;

import vk;
import logger;
import glfw;
import std::math;
import std::collections::list;
import std::collections::elastic_array;

const INIT_ENTITY_COUNT = 100;

bitstruct WindowEvents : char
{
	bool exit_scheduled;
	bool resize_scheduled;
}

struct VulkanRenderer
{
	App* app_ctx;
	List{Entity} entities;
	Mat4 view;
	Mat4 proj;
	VulkanElementBuffer{ushort} elem_buff;
	Camera camera;
	DeltaClock frame_clock;
	VkViewport viewport;
	VkRect2D scissors;
	WindowEvents window_events;
	ColorRGBA clear_color;
	uint frame_counter @if($feature(SF_FRAME_COUNT));
}

fn void VulkanRenderer.init(
	&renderer,
	App* app_ctx,
	VkExtent2D init_area,
	ColorRGBA init_clear_color
)
{
	renderer.clear_color = init_clear_color;
	renderer.viewport = {
		.x = 0.0f,
		.y = 0.0f,
		.height = (float)init_area.height, // NOTE: should be configurable and passed to perspective()
		.width = (float)init_area.width,
		.minDepth = 0.0f,
		.maxDepth = 1.0f,
	};
	renderer.scissors = { .offset = engine::OFFSET_START, .extent = init_area };

	init_elem_buffer{ushort}(
		&renderer.elem_buff,
		&app_ctx.vk_ctx,
		engine::get_cube_vertices()[..],
		engine::get_cube_indices(ushort)[..]
	)!!;

	renderer.camera.init({ 0, 0.5, 4 }, engine::V3_FAR);
	renderer.update_view_projection();

	initialize_event_handlers(&app_ctx.event_sys);

	$if $feature(SF_FRAME_COUNT):
		renderer.frame_counter = 0;
	$endif
	renderer.app_ctx = app_ctx;

	// --- Entities ---
	renderer.entities.init(&app_ctx.persistent_alloc, INIT_ENTITY_COUNT);
	GeometryView geometry = renderer.elem_buff.get_full_geometry_view();
	renderer.add_entity(geometry, { "grass.jpg" }, translation: { 0, 2, 0 });
	renderer.add_entity(geometry, { "painting.jpg" }, translation: { 2, 3.5, -3 });
	renderer.add_entity(geometry, { "soil.jpg" }, translation: { 0.7, -0.1, 0 });
	renderer.add_entity(geometry, { "sand.jpg" }, translation: { -0.1, 0.8, 0 });
	renderer.add_entity(geometry, { "metal.jpg" }, translation: { 0.4, 0.4, -1.0 });
	renderer.add_entity(geometry, { "water.jpg" }, translation: { 0.7, 0.7, 1.0 });
	renderer.add_entity(geometry, { "stones.jpg" }, translation: { 0.7, 0.6, -3.0 });

	FrameData* frame = app_ctx.vk_ctx.access_curr_frame_data();
	transfer_initial_entity_resources(app_ctx, renderer.entities.view(), &frame.transfer_cmd_buff);
}

fn void VulkanRenderer.start_clock(&renderer)
{
	renderer.frame_clock.start();
}

fn SwapchainPresentRes begin_frame(App* app_ctx)
{
	VulkanContext* vk_ctx = &app_ctx.vk_ctx;
	vk_ctx.swapchain.recreate_if_needed(vk_ctx);
	FrameData* frame = vk_ctx.access_curr_frame_data();
	
	return vk_ctx.swapchain.acquire_next_image_index(
		vk_ctx,
		0,
		frame.image_avail_sem.handle
	);
}

fn void draw_frame(App* app_ctx)
{
	VulkanContext* vk_ctx = &app_ctx.vk_ctx;
	FrameData* frame = vk_ctx.access_curr_frame_data();
	VulkanRenderer* renderer = &vk_ctx.renderer;
	VulkanElementBuffer{ushort}* elem_buff = &renderer.elem_buff;
	VulkanShader* shader = vk_ctx.access_curr_shader();
	VulkanPipeline* pipeline = shader.get_curr_pipeline();
	uint curr_frame = vk_ctx.curr_frame;

	// --- Step: transfer resources
	frame.transfer_cmd_buff.begin_recording();

	if (renderer.window_events.resize_scheduled || renderer.camera.dirty)
	{
		// NOTE: (HACK) only start receiving move events when first resize happens
		// because it will have big mouse delta to go from init hardcoded window coords
		// to actual window coords
		if (!app_ctx.input_sys.accept_move_events && renderer.window_events.resize_scheduled)
		{
			app_ctx.input_sys.accept_move_events = true;
		}
		renderer.update_view_projection();
	}

	VkBufferCopy copy_region = { .srcOffset = 0, .dstOffset = 0, .size = elem_buff.all_size_bytes, };
	cmd_copy_data_between_buff(frame.transfer_cmd_buff, elem_buff.staging_buff, elem_buff.main_buff, &copy_region);
	frame.transfer_cmd_buff.end_recording();

	VkSubmitInfo transfer_submit_info = {
		.sType = vk::STRUCTURE_TYPE_SUBMIT_INFO,
		.commandBufferCount = 1,
		.pCommandBuffers = &frame.transfer_cmd_buff.handle,
		.signalSemaphoreCount = 1,
		.pSignalSemaphores = &frame.transfer_end_sem.handle,
	};

	frame.transfer_cmd_buff.submit(vk_ctx, vk_ctx.dev.transfer_queue, &transfer_submit_info, null);

	// --- Step: bind resources
	frame.graphics_cmd_buff.begin_recording();
	elem_buff.cmd_bind(frame.graphics_cmd_buff);
	pipeline.cmd_bind(frame.graphics_cmd_buff);
	cmd_set_viewport_scissors(frame.graphics_cmd_buff, renderer);

	// --- Step: draw into the render target
	begin_rendering(vk_ctx, frame.graphics_cmd_buff);

	foreach (&entity : vk_ctx.renderer.entities)
	{
		cmd_push_mvp(
			frame.graphics_cmd_buff,
			pipeline,
			entity.get_model({ SCALE, ROTATION, TRANSLATION }),
			renderer.view,
			renderer.proj
		);

		update_entity(entity, app_ctx, shader, curr_frame);
		bind_entity(entity, shader, pipeline, frame.graphics_cmd_buff, curr_frame);
		cmd_draw_geometry(frame.graphics_cmd_buff, entity.geometry);
	}

	end_rendering(vk_ctx, frame.graphics_cmd_buff);
	frame.graphics_cmd_buff.end_recording();

	// --- Step submit graphics buffer
	VkSemaphore[*] wait_semaphores = { frame.image_avail_sem.handle, frame.transfer_end_sem.handle };
	VkPipelineStageFlags[wait_semaphores.len] wait_dest_mask = {
		vk::PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
		vk::PIPELINE_STAGE_VERTEX_INPUT_BIT
	};

	VkSubmitInfo submit_info = {
		.sType = vk::STRUCTURE_TYPE_SUBMIT_INFO,
		.waitSemaphoreCount = wait_semaphores.len,
		.pWaitSemaphores = &wait_semaphores,
		.pWaitDstStageMask = &wait_dest_mask,
		.commandBufferCount = 1,
		.pCommandBuffers = &frame.graphics_cmd_buff.handle,
		.signalSemaphoreCount = 1,
		.pSignalSemaphores = &frame.render_end_sem.handle,
	};

	frame.graphics_cmd_buff.submit(vk_ctx, vk_ctx.dev.graphics_queue, &submit_info, &frame.render_end_fence);
	vk_ctx.swapchain.present(vk_ctx, vk_ctx.dev.present_queue, frame.render_end_sem.handle);

	$if ($feature(SF_FRAME_COUNT)):
		logger::logn(INFO, "frame count: %d", renderer.frame_counter++);
	$endif
}

<*
 @return "false if should exit application"
*>
fn bool end_frame(App* app_ctx)
{
	VulkanContext* vk_ctx = &app_ctx.vk_ctx;
	FrameData* frame = vk_ctx.access_curr_frame_data();
	frame.render_end_fence.wait(vk_ctx)!!;
	frame.render_end_fence.reset(vk_ctx);
	frame.transfer_cmd_buff.reset();
	frame.graphics_cmd_buff.reset();
	vk_ctx.renderer.frame_clock.update();
	app_ctx.input_sys.update();
	vk_ctx.advance_frame();
	return !vk_ctx.renderer.window_events.exit_scheduled;
}

// TODO: should be scene::add_entity()
fn void VulkanRenderer.add_entity(
	&renderer,
	GeometryView geometry,
	String[] texture_names,
	Vec3 scale = { 1, 1, 1 },
	Quat rotation = quaternion::IDENTITY,
	Vec3 translation = { 0, 0, 0 }
)
{
	renderer.entities.push(
		engine::create_entity(
			renderer.app_ctx,
			renderer.app_ctx.vk_ctx.access_curr_shader(),
			geometry,
			texture_names,
			scale,
			rotation,
			translation
		)
	);
}

fn void update_entity(Entity* entity, App* app_ctx, VulkanShader* shader, uint curr_frame) @local
{
	VulkanContext* vk_ctx = &app_ctx.vk_ctx;
	ElasticArray{DescriptorUpdateInfo, vk::MAX_DESCRIPTOR_BINDING_COUNT} update_infos;
	entity.write_updates_for_shader(&app_ctx.tex_sys, &update_infos);
	shader.update_entity_resources(vk_ctx, entity.shader_state, update_infos.view(), curr_frame);
}

fn void bind_entity(
	Entity* entity,
	VulkanShader* shader,
	VulkanPipeline* pipeline,
	VulkanCmdBuffer cmd_buff,
	uint curr_frame
) @local
{
	shader.cmd_bind_entity_resources(cmd_buff, entity.shader_state, pipeline, curr_frame);
}

// TODO: implement this logic at runtime (with events, threads + ringbuffer)
fn void transfer_initial_entity_resources(App* app, Entity[] entities, VulkanCmdBuffer* cmd_buff)
{
	usz count = 0;
	foreach (&en : entities)
	{
		count += en.texture_indices.size;
	}

	uint[] indices = alloc::alloc_array(&app.temp_alloc, uint, count);
	defer alloc::free(&app.temp_alloc, indices);

	usz offset = 0;
	foreach (&en : entities)
	{
		mem::copy(indices.ptr + offset, en.texture_indices.data(), en.texture_indices.byte_size());
		offset += en.texture_indices.size;
	}

	cmd_buff.begin_recording();
	app.tex_sys.cmd_transfer_multiple_textures_to_gpu(&app.vk_ctx, indices, *cmd_buff);
	cmd_buff.end_recording();

	VkSubmitInfo submit_info = {
		.sType = vk::STRUCTURE_TYPE_SUBMIT_INFO,
		.commandBufferCount = 1,
		.pCommandBuffers = &cmd_buff.handle,
	};

	cmd_buff.submit(&app.vk_ctx, app.vk_ctx.dev.transfer_queue, &submit_info, null);
	check(vk::queueWaitIdle(app.vk_ctx.dev.transfer_queue));
	cmd_buff.reset();
}

fn void VulkanRenderer.set_clear_color(&renderer, ColorRGBA clear_color = COLOR_BLACK_RGBA) @inline
{
	renderer.clear_color = clear_color;
}

fn void VulkanRenderer.update_viewport_scissors(&renderer, VkExtent2D area)
{
	renderer.viewport.width = (float)area.width;
	renderer.viewport.height = (float)area.height;
	renderer.scissors.extent = area;
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

fn bool VulkanRenderer.should_close(&renderer) @inline
{
	return renderer.window_events.exit_scheduled;
}

<*
 @require cmd_buffer.state == VulkanCmdBufferState.RECORDING_BEGIN : "Should be in RECORDING_BEGIN state before 'begin_rendering'"
*>
fn void begin_rendering(VulkanContext* ctx, VulkanCmdBuffer cmd_buffer)
{
	VulkanSwapchain* swapchain = &ctx.swapchain;
	VkImage curr_image = swapchain.access_curr_image();
	VkImageView curr_view = swapchain.access_curr_view();

	cmd_transition_layout_raw_image(
		curr_image,
		cmd_buffer,
		vk::IMAGE_LAYOUT_UNDEFINED,
		vk::IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
		vk::PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		vk::PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
		0,
		vk::ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
		false
	);

	cmd_transition_layout_raw_image(
		ctx.swapchain.depth_image.handle,
		cmd_buffer,
		vk::IMAGE_LAYOUT_UNDEFINED,
		vk::IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		vk::PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		vk::PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
		0,
		vk::ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | vk::ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
		true
	);

	VkRenderingAttachmentInfo color_attachment_info = {
		.sType = vk::STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
		.imageView = curr_view,
		.imageLayout = vk::IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
		.loadOp = vk::ATTACHMENT_LOAD_OP_CLEAR,
		.storeOp = vk::ATTACHMENT_STORE_OP_STORE,
		.clearValue = { .color = { .float32 = ctx.renderer.clear_color } },
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
		.renderArea = { .offset = engine::OFFSET_START, .extent = ctx.renderer.scissors.extent },
		.layerCount = 1,
		.colorAttachmentCount = 1,
		.pColorAttachments = &color_attachment_info,
		.pDepthAttachment = &depth_attachment_info,
	};

	cmd_begin_rendering(cmd_buffer, &rendering_info);
}

fn void end_rendering(VulkanContext* ctx, VulkanCmdBuffer cmd_buffer)
{
	cmd_end_rendering(cmd_buffer);
	VulkanSwapchain* swapchain = &ctx.swapchain;

	cmd_transition_layout_raw_image(
		swapchain.access_curr_image(),
		cmd_buffer,
		vk::IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
		vk::IMAGE_LAYOUT_PRESENT_SRC_KHR,
		vk::PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		vk::PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
		0,
		vk::ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
		false
	);

	cmd_transition_layout_raw_image(
		swapchain.depth_image.handle,
		cmd_buffer,
		vk::IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
		vk::IMAGE_LAYOUT_PRESENT_SRC_KHR,
		vk::PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		vk::PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
		0,
		vk::ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | vk::ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
		true
	);
}

// --- Global descriptors (view & projection matrices)

<*
 @require renderer.window_events.resize_scheduled || renderer.camera.dirty : "One of these conditions should be true"
*>
fn void VulkanRenderer.update_view_projection(&renderer)
{
	renderer.view = renderer.camera.look_at();
	renderer.proj = matrix::perspective{float}(
		math::deg_to_rad(45.0f),
		renderer.aspect_ratio(),
		0.1f,
		100.0f
	);
	renderer.window_events.resize_scheduled = false;
	renderer.camera.dirty = false;
}

<*
 Inteded for calling from external modules
*>
fn void VulkanRenderer.set_view_projection(&renderer, Mat4 view, Mat4 proj)
{
	renderer.view = view;
	renderer.proj = proj;
}

<*
 Inteded for calling from external modules
*>
fn void VulkanRenderer.set_view(&renderer, Mat4 view)
{
	renderer.view = view;
}

<*
 Inteded for calling from external modules
*>
fn void VulkanRenderer.set_proj(&renderer, Mat4 proj)
{
	renderer.proj = proj;
}

fn void VulkanRenderer.destroy(&renderer)
{
	renderer.entities.free();
}

// --- Commands ---

fn void cmd_begin_rendering(VulkanCmdBuffer cmd_buff, VkRenderingInfo* rendering_info)
{
	vk::cmdBeginRendering(cmd_buff.handle, rendering_info);
}

fn void cmd_end_rendering(VulkanCmdBuffer cmd_buff)
{
	vk::cmdEndRendering(cmd_buff.handle);
}

fn void cmd_draw_geometry(VulkanCmdBuffer cmd_buff, GeometryView view)
{
	vk::cmdDrawIndexed(cmd_buff.handle, view.indices_count, 1, view.indices_offset, view.vertices_offset, 0);
}

fn void cmd_set_viewport_scissors(VulkanCmdBuffer cmd_buffer, VulkanRenderer* renderer)
{
	vk::cmdSetViewport(cmd_buffer.handle, 0, 1, &renderer.viewport);
	vk::cmdSetScissor(cmd_buffer.handle, 0, 1, &renderer.scissors);
}

fn void cmd_push_mvp(VulkanCmdBuffer cmd_buffer, VulkanPipeline* pipeline, Mat4 model, Mat4 view, Mat4 proj)
{
	Mat4 mvp = proj * view * model;
	vk::cmdPushConstants(cmd_buffer.handle, pipeline.layout, vk::SHADER_STAGE_VERTEX_BIT, 0, Mat4::size, &mvp);
}

// --- Event handlers ---

fn void initialize_event_handlers(EventSystem* ev_sys) @local
{
	ev_sys.add_event_handler(MOUSE_MOVE, &handle_mouse_move);
	ev_sys.add_event_handler(KEY_DOWN, &handle_key_down_renderer);
	ev_sys.add_event_handler(KEY_DOWN, &handle_key_down_camera);
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

fn bool handle_key_down_renderer(EventContext ctx, void* listener) @local
{
	VulkanRenderer* renderer = (VulkanRenderer*)listener;
	uint key = ctx.u32[0];
	if (key == glfw::KEY_ESCAPE)
	{
		renderer.window_events.exit_scheduled = true;
	}
	return false;
}

fn bool handle_key_down_camera(EventContext ctx, void* listener) @local
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
