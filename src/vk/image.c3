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
	VulkanContext* ctx,
	VulkanImage* out_image,
    VkFormat format,
    uint width,
    uint height,
	uint depth = 1u,
    VkImageUsageFlags usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    VkImageAspectFlags aspect_flags = VK_IMAGE_ASPECT_COLOR_BIT,
    VkImageLayout init_layout = VK_IMAGE_LAYOUT_UNDEFINED,
    VkMemoryPropertyFlagBits mem_flags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    VkImageType type = VK_IMAGE_TYPE_2D,
    VkImageTiling tiling = VK_IMAGE_TILING_OPTIMAL,
    VkSampleCountFlagBits sample_count = VK_SAMPLE_COUNT_1_BIT,
    bool should_create_view = true,
) {
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
	    .sharing_mode = ctx.swapchain.sharing_mode,
	    .initial_layout = init_layout,
	};

	vk_check(vkCreateImage(ctx.dev.log_dev, &image_ci, ctx.vk_alloc, &out_image.handle));

	out_image.width = width;
	out_image.height = height;
	out_image.depth = depth;
	out_image.type = type;
	out_image.format = format;
	out_image.aspect_flags = aspect_flags;

    VkMemoryRequirements mem_reqs @noinit;
    vkGetImageMemoryRequirements(ctx.dev.log_dev, out_image.handle, &mem_reqs);

	uint? mem_type_ind = ctx.dev.find_mem_type_index(mem_reqs.memory_type_bits, mem_flags).get();
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

    vk_check(vkAllocateMemory(ctx.dev.log_dev, &alloc_info, ctx.vk_alloc, &out_image.memory));
    vk_check(vkBindImageMemory(ctx.dev.log_dev, out_image.handle, out_image.memory, 0));

    if (should_create_view) {
        out_image.create_view(ctx, aspect_flags);
    }

    return true;
}

fn void VulkanImage.create_view(&image, VulkanContext* ctx, VkImageAspectFlags aspect_flags = VK_IMAGE_ASPECT_COLOR_BIT)
{
	image.view = create_view_from_raw(ctx, image.handle, image.format, (VkImageViewType)image.type, aspect_flags);
}

fn VkImageView create_view_from_raw(
	VulkanContext* ctx,
	VkImage raw_image,
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

    vk_check(vkCreateImageView(ctx.dev.log_dev, &image_view_ci, ctx.vk_alloc, &view));
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

fn void VulkanImage.destroy(&image, VulkanContext* ctx)
{
	if (image.handle != null) {
	    vkDestroyImageView(ctx.dev.log_dev, image.view, ctx.vk_alloc);
	    vkFreeMemory(ctx.dev.log_dev, image.memory, ctx.vk_alloc);
	    vkDestroyImage(ctx.dev.log_dev, image.handle, ctx.vk_alloc);
	    image.view = null;
	    image.memory = null;
	    image.handle = null;
	}
}
