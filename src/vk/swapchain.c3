module vk;

import std::collections::elastic_array;
import std::collections::maybe;
import std::math;
import logger;

const MAX_SWAPCHAIN_IMG_CNT = 5u;

faultdef FAILED_TO_ACQUIRE_NEXT_IMAGE_INDEX;

struct VulkanSwapchain
{
	ElasticArray{VkImage, MAX_SWAPCHAIN_IMG_CNT} 		images;
	ElasticArray{VkImageView, MAX_SWAPCHAIN_IMG_CNT} 	image_views;
	VulkanImage					depth_image;
	VkSwapchainKHR				handle;
	VkPresentModeKHR			present_mode;
	VkSurfaceFormatKHR			surface_fmt;
	VkSharingMode				sharing_mode;
	uint 						curr_image_index;
	bool 						recreation_scheduled;
}

enum SwapchainPresentRes
{
	SUCCESS,
	NEEDS_RECREATION,
}

faultdef
	SWAPCHAIN_FAILED_TO_FIND_FORMAT,
	SWAPCHAIN_FAILED_TO_CREATE_DEPTH_IMAGE;

fn void? init_swapchain(VulkanContext* ctx, VkExtent2D extent)
{
	if (catch excuse = ctx.swapchain.acquire_format_and_present_mode(&ctx.dev.swapchain_supp_info)) {
		logger::logn(FATAL, "Failed to acquire appropriate format for swapchain");
		return excuse~;
	}
	if (catch excuse = ctx.swapchain.create_inner(ctx, extent)) {
		logger::logn(FATAL, "Failed create swapchain");
		return excuse~;
	}
}

fn SwapchainPresentRes VulkanSwapchain.acquire_next_image_index(
	&swapchain,
    VulkanContext* ctx,
    ulong timeout_ns,
    VkSemaphore image_available_semaphore,
)
{
	uint image_index @noinit;
	VkResult result = VK_NOT_READY;

	do {
	    result = vkAcquireNextImageKHR(ctx.dev.log_dev, swapchain.handle, timeout_ns, image_available_semaphore, null, &image_index);
	} while (result == VK_NOT_READY);

    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
        logger::logn(WARN, "Swapchain is outdated, scheduling recreation...");
		swapchain.recreation_scheduled = true;
		return NEEDS_RECREATION;
    }
    else if (result != VK_SUCCESS) {
        logger::logn(FATAL, "Failed to acquire swapchain image, reason: %s", result);
		abort();
    }
	swapchain.curr_image_index = image_index;
	return SUCCESS;
}

fn SwapchainPresentRes VulkanSwapchain.present(
	&swapchain,
    VulkanContext* ctx,
    VkQueue present_queue,
    VkSemaphore render_complete_semaphore,
)
{
    VkPresentInfoKHR present_info = {
        .s_type = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .wait_semaphore_count = 1u,
        .p_wait_semaphores = &render_complete_semaphore,
        .swapchain_count = 1u,
        .p_swapchains = &swapchain.handle,
        .p_image_indices = &swapchain.curr_image_index,
        .p_results = null,
    };

    VkResult result = vkQueuePresentKHR(present_queue, &present_info);
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
        logger::logn(WARN, "Swapchain is outdated, recreating...");
		swapchain.recreation_scheduled = true;
		return NEEDS_RECREATION;
    } else if (result != VK_SUCCESS) {
        logger::logn(FATAL, "Failed to present swapchain image, reason: %d", result);
		abort();
    }
	return SUCCESS;
}

fn void? VulkanSwapchain.recreate(&swapchain, VulkanContext* ctx, VkExtent2D extent)
{
	vkDeviceWaitIdle(ctx.dev.log_dev);
	swapchain.destroy(ctx);
	swapchain.create_inner(ctx, extent)!;
	swapchain.recreation_scheduled = false;
}

fn void? VulkanSwapchain.create_inner(&swapchain, VulkanContext* ctx, VkExtent2D extent)
{
	VulkanDevice* dev = &ctx.dev;
	SwapchainSupportInfo* supp_info = &dev.swapchain_supp_info;
	
	VkExtent2D min_extent = supp_info.capabilities.min_image_extent;
	VkExtent2D max_extent = supp_info.capabilities.max_image_extent;
	extent.width = math::clamp(extent.width, min_extent.width, max_extent.width);
	extent.height = math::clamp(extent.height, min_extent.height, max_extent.height);

    uint create_image_count = supp_info.capabilities.min_image_count + 1;
    if (supp_info.capabilities.max_image_count > 0 && create_image_count > supp_info.capabilities.max_image_count) {
        create_image_count = supp_info.capabilities.max_image_count;
    }

	VkSwapchainCreateInfoKHR swapchain_ci = {
		.s_type = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
		.surface = ctx.surface,
		.min_image_count = create_image_count,
	    .image_format = swapchain.surface_fmt.format,
	    .image_color_space = swapchain.surface_fmt.color_space,
	    .image_extent = extent,
	    .image_array_layers = 1,
	    .image_usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
	    .pre_transform = supp_info.capabilities.current_transform,
	    .composite_alpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
	    .present_mode = swapchain.present_mode,
	    .old_swapchain = null,
	};

    if (dev.queue_indices.graphics.fam != dev.queue_indices.present.fam) {
        uint[2] queue_indices = { dev.queue_indices.graphics.fam, dev.queue_indices.present.fam };
		swapchain.sharing_mode = VK_SHARING_MODE_CONCURRENT;
        swapchain_ci.image_sharing_mode = VK_SHARING_MODE_CONCURRENT;
        swapchain_ci.queue_family_index_count = queue_indices.len;
        swapchain_ci.p_queue_family_indices = &queue_indices;
    } else {
		swapchain.sharing_mode = VK_SHARING_MODE_EXCLUSIVE;
        swapchain_ci.image_sharing_mode = VK_SHARING_MODE_EXCLUSIVE;
        swapchain_ci.queue_family_index_count = 0;
        swapchain_ci.p_queue_family_indices = null;
    }

	vk_check(vkCreateSwapchainKHR(dev.log_dev, &swapchain_ci, ctx.vk_alloc, &ctx.swapchain.handle));

	uint actual_image_cnt @noinit;
	vk_check(vkGetSwapchainImagesKHR(dev.log_dev, swapchain.handle, &actual_image_cnt, null));

	actual_image_cnt = math::min(MAX_SWAPCHAIN_IMG_CNT, actual_image_cnt);
	if (swapchain.images.size != actual_image_cnt) {
		swapchain.images.resize(actual_image_cnt);
	}
	if (swapchain.image_views.size != actual_image_cnt) {
		swapchain.image_views.resize(actual_image_cnt);
	}
	
	vk_check(vkGetSwapchainImagesKHR(dev.log_dev, swapchain.handle, &actual_image_cnt, swapchain.images.data()));

	foreach (usz ind, &view : swapchain.image_views) {
        *view = create_view_from_raw(ctx, swapchain.images[ind], swapchain.surface_fmt.format);
    }

    if (!dev.detect_depth_format()) {
        dev.depth_fmt = VK_FORMAT_UNDEFINED;
        logger::logn(FATAL, "Failed to find a supported format");
		return SWAPCHAIN_FAILED_TO_FIND_FORMAT~;
    }

	if (!create_image(
		ctx, &swapchain.depth_image, dev.depth_fmt,
		extent.width, extent.height, 1u,
		VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
	    VK_IMAGE_ASPECT_DEPTH_BIT,
	    VK_IMAGE_LAYOUT_UNDEFINED,
	    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
	)) {
		logger::logn(FATAL, "Failed to create a depth image");
		return SWAPCHAIN_FAILED_TO_CREATE_DEPTH_IMAGE~;
	}

	swapchain.curr_image_index = 0;
	logger::logn(INFO, "Swapchain created successfully!");
	logger::logn(INFO, "Image sharing mode: %s", swapchain.sharing_mode == VK_SHARING_MODE_CONCURRENT ? "Concurrent" : "Exclusive");
}

fn VkImage VulkanSwapchain.access_curr_image(&swapchain) @inline
{
	return swapchain.images[swapchain.curr_image_index];
}

fn VkImageView VulkanSwapchain.access_curr_view(&swapchain) @inline
{
	return swapchain.image_views[swapchain.curr_image_index];
}

fn void? VulkanSwapchain.acquire_format_and_present_mode(&swapchain, SwapchainSupportInfo* supp_info)
{
	bool found = false;
	foreach (&fmt : supp_info.formats) {
		if (fmt.format == VK_FORMAT_B8G8R8A8_SRGB && fmt.color_space == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
		{
			found = true;
			swapchain.surface_fmt = *fmt;
			break;
		}
	}
	if (!found) {
		return SWAPCHAIN_FAILED_TO_FIND_FORMAT~;
	}

	VkPresentModeKHR selected_mode = VK_PRESENT_MODE_FIFO_KHR;
	foreach (&mode : supp_info.present_modes) {
		if (*mode == VK_PRESENT_MODE_MAILBOX_KHR) {
			selected_mode = *mode;
		}
	}
	swapchain.present_mode = selected_mode;
}

fn void VulkanSwapchain.destroy(&swapchain, VulkanContext* ctx)
{
	if (swapchain.handle) {
		vkDestroySwapchainKHR(ctx.dev.log_dev, swapchain.handle, ctx.vk_alloc);
		swapchain.handle = null;
	}
}
