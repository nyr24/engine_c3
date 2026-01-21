module vk;

import logger;
import std::collections::maybe;

struct VulkanImage {
    VkImage handle;
    VkImageView view;
    VkDeviceMemory memory;
    uint width;
    uint height;
	uint depth;
    VkImageType type;
    VkFormat format;
	VkImageAspectFlags aspect_flags;
}

fn bool create_image(
	VulkanContext* context,
	VulkanImage* out_image,
    VkFormat format,
    VkImageUsageFlags usage,
    uint width,
    uint height,
	uint depth = 1u,
    VkImageTiling tiling = VK_IMAGE_TILING_OPTIMAL,
    VkMemoryPropertyFlagBits mem_flags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    VkSampleCountFlagBits sample_count = VK_SAMPLE_COUNT_1_BIT,
    VkImageAspectFlags aspect_flags = VK_IMAGE_ASPECT_COLOR_BIT,
    VkImageLayout init_layout = VK_IMAGE_LAYOUT_UNDEFINED,
    VkImageType type = VK_IMAGE_TYPE_2D,
    bool should_create_view = true,
) {
	VkDevice log_dev = context.dev.log_dev;

	VkImageCreateInfo image_ci = {
	    .s_type = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
	    .p_next = null,
	    .image_type = type,
	    .format = format,
	    .extent = {
	        .width = width,
	        .height = height,
	        .depth = depth,
	    },
	    .mip_levels = 4u,
	    .array_layers = 1u,
	    .samples = sample_count,
	    .tiling = tiling,
	    .usage = usage,
	    .sharing_mode = context.swapchain.sharing_mode,
	    .initial_layout = init_layout,
	};

	vk_check(vkCreateImage(log_dev, &image_ci, null, &out_image.handle));

	out_image.width = width;
	out_image.height = height;
	out_image.depth = depth;
	out_image.type = type;
	out_image.format = format;
	out_image.aspect_flags = aspect_flags;

    VkMemoryRequirements mem_reqs @noinit;
    vkGetImageMemoryRequirements(log_dev, out_image.handle, &mem_reqs);

	uint? mem_type_ind = context.dev.find_mem_type_index(mem_reqs.memory_type_bits, mem_flags).get();
	if (catch err = mem_type_ind) {
        logger::@logn(LogLevel.FATAL, "Required memory type wasn't found. Image is not valid");
        return false;
    };

    VkMemoryAllocateInfo alloc_info = {
        .s_type = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .p_next = null,
        .allocation_size = mem_reqs.size,
        .memory_type_index = mem_type_ind,
    };

    vk_check(vkAllocateMemory(log_dev, &alloc_info, null, &out_image.memory));
    vk_check(vkBindImageMemory(log_dev, out_image.handle, out_image.memory, 0));

    if (should_create_view) {
        out_image.create_view(log_dev, aspect_flags);
    }

    return true;
}

fn void VulkanImage.create_view(&image, VulkanDevice* dev, VkImageAspectFlags aspect_flags = VK_IMAGE_ASPECT_COLOR_BIT)
{
	image.view = create_view_from_raw(image.handle, dev, image.format, (VkImageViewType)image.type, aspect_flags);
}

fn VkImageView create_view_from_raw(
	VkImage raw_image,
	VulkanDevice* dev,
	VkFormat format,
	VkImageViewType type = VK_IMAGE_TYPE_2D,
	VkImageAspectFlags aspect_flags = VK_IMAGE_ASPECT_COLOR_BIT,
)
{
    VkImageView view @noinit;

    VkImageViewCreateInfo image_view_ci = {
        .s_type = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .p_next = null,
        .image = raw_image,
        .view_type = type,
        .format = format,
        .subresource_range = {
            .aspect_mask = aspect_flags,
            .base_mip_level = 0,
            .level_count = VK_REMAINING_MIP_LEVELS,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    vk_check(vkCreateImageView(dev.log_dev, &image_view_ci, null, &view));
    return view;
}

fn void VulkanImage.cmd_transition_layout(
	&image,
    VulkanCmdBuffer* cmd_buffer,
    VkImageLayout src_layout,
    VkImageLayout dest_layout,
    VkPipelineStageFlagBits2 src_stage_mask,
    VkPipelineStageFlagBits2 dest_stage_mask,
    VkAccessFlagBits2 src_access_mask,
    VkAccessFlagBits2 dest_access_mask,
)
{
	cmd_transition_layout_raw(
		image.handle,
		cmd_buffer,
	    src_layout,
	    dest_layout,
	    src_stage_mask,
	    dest_stage_mask,
	    src_access_mask,
	    dest_access_mask,
		(image.aspect_flags & VK_IMAGE_ASPECT_DEPTH_BIT) > 0,
	);
}

fn void cmd_transition_layout_raw(
    VkImage raw_image,
    VulkanCmdBuffer* cmd_buffer,
    VkImageLayout src_layout,
    VkImageLayout dest_layout,
    VkPipelineStageFlagBits2 src_stage_mask,
    VkPipelineStageFlagBits2 dest_stage_mask,
    VkAccessFlagBits2 src_access_mask,
    VkAccessFlagBits2 dest_access_mask,
    bool is_depth,
)
{
    VkImageMemoryBarrier2 barrier = {
        .s_type = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .src_stage_mask = src_stage_mask,
        .src_access_mask = src_access_mask,
        .dst_stage_mask = dest_stage_mask,
        .dst_access_mask = dest_access_mask,
        .old_layout = src_layout,
        .new_layout = dest_layout,
        .src_queue_family_index = VK_QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = VK_QUEUE_FAMILY_IGNORED,
        .image = raw_image,
        .subresource_range = {
            .aspect_mask = is_depth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT,
            .base_mip_level = 0,
            .level_count = VK_REMAINING_MIP_LEVELS,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    VkDependencyInfo deps_info = {
        .s_type = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .dependency_flags = 0,
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &barrier,
    };

    vkCmdPipelineBarrier2(cmd_buffer.handle, &deps_info);
}

fn void VulkanImage.destroy(&image, VulkanDevice* dev)
{
	if (image.handle != null) {
	    vkDestroyImageView(dev.log_dev, image.view, null);
	    vkFreeMemory(dev.log_dev, image.memory, null);
	    vkDestroyImage(dev.log_dev, image.handle, null);
	    image.view = null;
	    image.memory = null;
	    image.handle = null;
	}
}
