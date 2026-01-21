module vk;

import std::collections::elastic_array;
import std::collections::maybe;
import std::math;
import logger;

const MAX_SWAPCHAIN_IMG_CNT = 5u;

struct VulkanSwapchain {
	ElasticArray{VkImage, MAX_SWAPCHAIN_IMG_CNT} 		images;
	ElasticArray{VkImageView, MAX_SWAPCHAIN_IMG_CNT} 	image_views;
	VkImage						depth_image;
	VkSwapchainKHR				handle;
	VkPresentModeKHR			present_mode;
	VkSurfaceFormatKHR			surface_fmt;
	VkSharingMode				sharing_mode;
}

fn bool init_swapchain(VulkanContext* context, Maybe{VkExtent2D} mb_extent)
{
	if (!context.swapchain.acquire_format_and_present_mode(&context.dev.swapchain_supp_info)) {
		logger::@logn(LogLevel.FATAL, "Failed to acquire appropriate format for swapchain");
		return false;
	}
	if (!context.swapchain.create_inner(context, mb_extent)) {
		logger::@logn(LogLevel.FATAL, "Failed create swapchain");
		return false;
	}

	return true;
}

// TODO: recreate
// fn bool VulkanSwapchain.recreate(&swapchain, VulkanContext* context, Maybe{VkExtent2D} mb_extent)
// {
	
// }

fn bool VulkanSwapchain.create_inner(&swapchain, VulkanContext* context, Maybe{VkExtent2D} mb_extent) @private
{
	VkExtent2D extent @noinit;
	VulkanDevice* dev = &context.dev;
	SwapchainSupportInfo* supp_info = &dev.swapchain_supp_info;
	
	if (try VkExtent2D t_extent = mb_extent.get()) {
		extent = t_extent;
		VkExtent2D min_extent = supp_info.capabilities.min_image_extent;
		VkExtent2D max_extent = supp_info.capabilities.max_image_extent;
		extent.width = math::clamp(extent.width, min_extent.width, max_extent.width);
		extent.height = math::clamp(extent.height, min_extent.height, max_extent.height);
	} else {
		extent = supp_info.capabilities.current_extent;
	}

    uint create_image_count = supp_info.capabilities.min_image_count + 1;
    if (supp_info.capabilities.max_image_count > 0 && create_image_count > supp_info.capabilities.max_image_count) {
        create_image_count = supp_info.capabilities.max_image_count;
    }

	VkSwapchainCreateInfoKHR swapchain_ci;
	swapchain_ci.s_type = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
	swapchain_ci.surface = context.surface;
	swapchain_ci.min_image_count = create_image_count;
    swapchain_ci.image_format = swapchain.surface_fmt.format;
    swapchain_ci.image_color_space = swapchain.surface_fmt.color_space;
    swapchain_ci.image_extent = extent;
    swapchain_ci.image_array_layers = 1;
    swapchain_ci.image_usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    swapchain_ci.pre_transform = supp_info.capabilities.current_transform;
    swapchain_ci.composite_alpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    swapchain_ci.present_mode = swapchain.present_mode;
    swapchain_ci.old_swapchain = null;

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

	vk_check(vkCreateSwapchainKHR(dev.log_dev, &swapchain_ci, null, &context.swapchain.handle));

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

	// TODO: create images

	return true;
}

fn bool VulkanSwapchain.acquire_format_and_present_mode(&swapchain, SwapchainSupportInfo* supp_info) @private
{
	bool found = false;
	foreach (&fmt : supp_info.formats) {
		if (fmt.format == VK_FORMAT_B8G8R8A8_SRGB && fmt.color_space == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
		{
			found = true;
			swapchain.surface_fmt = *fmt;
		}
	}
	if (!found) {
		return false;
	}

	VkPresentModeKHR selected_mode = VK_PRESENT_MODE_FIFO_KHR;
	foreach (&mode : supp_info.present_modes) {
		if (*mode == VK_PRESENT_MODE_MAILBOX_KHR) {
			selected_mode = *mode;
		}
	}
	swapchain.present_mode = selected_mode;
	return true;
}
