module engine::vk;

import vk;
import std::collections::elastic_array;
import std::collections::maybe;
import std::math;
import logger;

const MAX_SWAPCHAIN_IMG_CNT = 5u;

faultdef SWAPCHAIN_FAILED_TO_FIND_FORMAT
;

struct VulkanSwapchain
{
	ElasticArray{VkImage, MAX_SWAPCHAIN_IMG_CNT} images;
	ElasticArray{VkImageView, MAX_SWAPCHAIN_IMG_CNT} image_views;
	VulkanImage depth_image;
	VkSwapchainKHR handle;
	VkPresentModeKHR present_mode;
	VkSurfaceFormatKHR surface_fmt;
	VkSharingMode sharing_mode;
	uint curr_image_index;
	bool recreation_scheduled;
}

enum SwapchainPresentRes
{
	SUCCESS,
	NEEDS_RECREATION,
	NEEDS_RECREATION_CANT_PROCEED,
}

fn void? VulkanSwapchain.init(&swapchain, VulkanContext* ctx, VkExtent2D extent)
{
	swapchain.recreation_scheduled = false;
	if (catch err = ctx.swapchain.acquire_format_and_present_mode(&ctx.dev.swapchain_supp_info))
	{
		logger::logn(FATAL, "Failed to acquire appropriate format for swapchain");
		return err~;
	}
	if (catch err = swapchain.create_inner(ctx, extent))
	{
		logger::logn(FATAL, "Failed create swapchain");
		return err~;
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
	VkResult result = vk::NOT_READY;

	do
	{
		result = vk::acquireNextImageKHR(
			ctx.dev.log_dev,
			swapchain.handle,
			timeout_ns,
			image_available_semaphore,
			null,
			&image_index
		);
	} while (result == vk::NOT_READY);

	swapchain.curr_image_index = image_index;

	switch (result)
	{
		case vk::SUCCESS:
			return SUCCESS;
		case vk::SUBOPTIMAL_KHR:
			VkExtent2D new_coords = ctx.app_ctx.window.get_screen_coordinates();
			VkExtent2D curr_coords = ctx.renderer.get_extent();
			if (new_coords != curr_coords)
			{
				logger::logn(INFO, "Swapchain is outdated, scheduling recreation...");
				ctx.renderer.update_viewport_scissors(new_coords);
				swapchain.recreation_scheduled = true;
				return NEEDS_RECREATION;
			}
			return SUCCESS;
		case vk::ERROR_OUT_OF_DATE_KHR:
			logger::logn(WARN, "Swapchain is outdated, can't proceed next frame, scheduling recreation...");
			swapchain.recreation_scheduled = true;
			return NEEDS_RECREATION_CANT_PROCEED;
		default:
			logger::logn(FATAL, "Failed to acquire swapchain image, reason: %s", result);
			abort();
	}
}

fn SwapchainPresentRes VulkanSwapchain.present(
	&swapchain,
	VulkanContext* ctx,
	VkQueue present_queue,
	VkSemaphore render_complete_semaphore,
)
{
	VkPresentInfoKHR present_info = {
		.sType = vk::STRUCTURE_TYPE_PRESENT_INFO_KHR,
		.waitSemaphoreCount = 1u,
		.pWaitSemaphores = &render_complete_semaphore,
		.swapchainCount = 1u,
		.pSwapchains = &swapchain.handle,
		.pImageIndices = &swapchain.curr_image_index,
		.pResults = null,
	};

	VkResult result = vk::queuePresentKHR(present_queue, &present_info);
	switch (result)
	{
		case vk::SUCCESS:
			return SUCCESS;
		case vk::SUBOPTIMAL_KHR:
			VkExtent2D new_coords = ctx.app_ctx.window.get_screen_coordinates();
			VkExtent2D prev_coords = ctx.renderer.scissors.extent;
			if (new_coords != prev_coords)
			{
				logger::logn(INFO, "Swapchain is outdated, scheduling recreation...");
				swapchain.recreation_scheduled = true;
				return NEEDS_RECREATION;
			}
			return SUCCESS;
		case vk::ERROR_OUT_OF_DATE_KHR:
			logger::logn(WARN, "Swapchain is outdated, can't proceed next frame, scheduling recreation...");
			swapchain.recreation_scheduled = true;
			return NEEDS_RECREATION_CANT_PROCEED;
		default:
			logger::logn(FATAL, "Failed to present swapchain image, reason: %d", result);
			abort();
	}
}

fn void? VulkanSwapchain.recreate(&swapchain, VulkanContext* ctx, VkExtent2D extent)
{
	vk::deviceWaitIdle(ctx.dev.log_dev);
	swapchain.destroy(ctx);
	swapchain.create_inner(ctx, extent)!;
}

fn void VulkanSwapchain.recreate_if_needed(&swapchain, VulkanContext* ctx)
{
	if (@unlikely(swapchain.recreation_scheduled))
	{
		VkExtent2D new_coords = ctx.renderer.get_extent();
		logger::logn(INFO, "Recreating swapchain, new screen coordinates: %d %d", new_coords.width, new_coords.height);
		swapchain.recreate(ctx, new_coords)!!;
		swapchain.recreation_scheduled = false;
		ctx.renderer.window_events.resize_scheduled = true;
	}
}

fn void? VulkanSwapchain.create_inner(&swapchain, VulkanContext* ctx, VkExtent2D extent)
{
	VulkanDevice* dev = &ctx.dev;
	SwapchainSupportInfo* supp_info = &dev.swapchain_supp_info;

	VkExtent2D min_extent = supp_info.capabilities.minImageExtent;
	VkExtent2D max_extent = supp_info.capabilities.maxImageExtent;
	extent.width = math::max(extent.width, min_extent.width);
	extent.height = math::max(extent.height, min_extent.height);

	if (max_extent.width > min_extent.width)
	{
		extent.width = math::min(extent.width, max_extent.width);
		extent.height = math::min(extent.height, max_extent.height);
	}

	uint create_image_count = supp_info.capabilities.minImageCount + 1;
	if (supp_info.capabilities.maxImageCount > 0 && create_image_count > supp_info.capabilities.maxImageCount)
	{
		create_image_count = supp_info.capabilities.maxImageCount;
	}

	VkSwapchainCreateInfoKHR swapchain_ci = {
		.sType = vk::STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
		.surface = ctx.surface,
		.minImageCount = create_image_count,
		.imageFormat = swapchain.surface_fmt.format,
		.imageColorSpace = swapchain.surface_fmt.colorSpace,
		.imageExtent = extent,
		.imageArrayLayers = 1,
		.imageUsage = vk::IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
		.preTransform = supp_info.capabilities.currentTransform,
		.compositeAlpha = vk::COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
		.presentMode = swapchain.present_mode,
		.oldSwapchain = swapchain.handle,
		};

	if (dev.queue_indices.graphics.fam != dev.queue_indices.present.fam)
	{
		uint[2] queue_indices = { dev.queue_indices.graphics.fam, dev.queue_indices.present.fam };
		swapchain.sharing_mode = vk::SHARING_MODE_CONCURRENT;
		swapchain_ci.imageSharingMode = vk::SHARING_MODE_CONCURRENT;
		swapchain_ci.queueFamilyIndexCount = queue_indices.len;
		swapchain_ci.pQueueFamilyIndices = &queue_indices;
	}
	else
	{
		swapchain.sharing_mode = vk::SHARING_MODE_EXCLUSIVE;
		swapchain_ci.imageSharingMode = vk::SHARING_MODE_EXCLUSIVE;
		swapchain_ci.queueFamilyIndexCount = 0;
		swapchain_ci.pQueueFamilyIndices = null;
	}

	check(vk::createSwapchainKHR(dev.log_dev, &swapchain_ci, ctx.vk_alloc, &ctx.swapchain.handle));

	uint actual_image_cnt @noinit;
	check(vk::getSwapchainImagesKHR(dev.log_dev, swapchain.handle, &actual_image_cnt, null));

	actual_image_cnt = math::min(MAX_SWAPCHAIN_IMG_CNT, actual_image_cnt);
	if (swapchain.images.size != actual_image_cnt)
	{
		swapchain.images.resize(actual_image_cnt);
	}
	if (swapchain.image_views.size != actual_image_cnt)
	{
		swapchain.image_views.resize(actual_image_cnt);
	}

	check(vk::getSwapchainImagesKHR(dev.log_dev, swapchain.handle, &actual_image_cnt, swapchain.images.data()));

	foreach (usz ind, &view : swapchain.image_views)
	{
		*view = create_view_from_raw_image(ctx, swapchain.images[ind], swapchain.surface_fmt.format);
	}

	if (!dev.detect_depth_format())
	{
		dev.depth_fmt = vk::FORMAT_UNDEFINED;
		logger::logn(FATAL, "Failed to find a supported format");
		return SWAPCHAIN_FAILED_TO_FIND_FORMAT~;
	}

	swapchain.depth_image.init(
		ctx,
		dev.depth_fmt,
		extent.width,
		extent.height,
		1u,
		vk::IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
		vk::IMAGE_ASPECT_DEPTH_BIT,
		vk::IMAGE_LAYOUT_UNDEFINED,
		vk::MEMORY_PROPERTY_DEVICE_LOCAL_BIT
	);

	swapchain.curr_image_index = 0;
	logger::logn(INFO, "Swapchain created successfully!");
	logger::logn(
		INFO,
		"Image sharing mode: %s",
		swapchain.sharing_mode == vk::SHARING_MODE_CONCURRENT ? "Concurrent" : "Exclusive"
	);
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
	foreach (&fmt : supp_info.formats)
	{
		if (fmt.format == vk::FORMAT_B8G8R8A8_SRGB && fmt.colorSpace == vk::COLOR_SPACE_SRGB_NONLINEAR_KHR)
		{
			found = true;
			swapchain.surface_fmt = *fmt;
			break;
		}
	}
	if (!found)
	{
		return SWAPCHAIN_FAILED_TO_FIND_FORMAT~;
	}

	VkPresentModeKHR selected_mode = vk::PRESENT_MODE_FIFO_KHR;
	foreach (&mode : supp_info.present_modes)
	{
		if (*mode == vk::PRESENT_MODE_MAILBOX_KHR)
		{
			selected_mode = *mode;
		}
	}
	swapchain.present_mode = selected_mode;
}

fn void VulkanSwapchain.destroy(&swapchain, VulkanContext* ctx)
{
	if (swapchain.handle)
	{
		vk::destroySwapchainKHR(ctx.dev.log_dev, swapchain.handle, ctx.vk_alloc);
		swapchain.handle = null;
	}
}
