module vk;

import constants;
import std::math;

struct VulkanRenderer
{
	ColorRGBA   clear_color;
	VkViewport  viewport;
	VkRect2D	scissors;
}

fn void VulkanRenderer.init(&renderer, VkExtent2D init_area, ColorRGBA init_clear_color = COLOR_BLACK_RGBA)
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
		.offset = constants::OFFSET_START,
		.extent = init_area,
	};
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
        .clear_value = constants::CLEAR_DEPTH_VALUE,
    };

    VkRenderingInfo rendering_info = {
        .s_type = VK_STRUCTURE_TYPE_RENDERING_INFO,
        .render_area = { .offset = constants::OFFSET_START, .extent = ctx.renderer.scissors.extent },
        .layer_count = 1,
        .color_attachment_count = 1,
        .p_color_attachments = &color_attachment_info,
        .p_depth_attachment = &depth_attachment_info,
    };

    vkCmdBeginRendering(cmd_buffer.handle, &rendering_info);
}

fn void end_rendering(VulkanContext* ctx, VulkanCmdBuffer* cmd_buffer)
{
    vkCmdEndRendering(cmd_buffer.handle);
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

