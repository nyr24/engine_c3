module engine::vk;

import vk;
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
    VkImageUsageFlags usage = vk::IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    VkImageAspectFlags aspect_flags = vk::IMAGE_ASPECT_COLOR_BIT,
    VkImageLayout init_layout = vk::IMAGE_LAYOUT_UNDEFINED,
    VkMemoryPropertyFlagBits mem_flags = vk::MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    VkImageType type = vk::IMAGE_TYPE_2D,
    VkImageTiling tiling = vk::IMAGE_TILING_OPTIMAL,
    VkSampleCountFlagBits sample_count = vk::SAMPLE_COUNT_1_BIT,
    bool should_create_view = true,
) {
	VkImageCreateInfo image_ci = {
	    .sType = vk::STRUCTURE_TYPE_IMAGE_CREATE_INFO,
	    .pNext = null,
	    .imageType = type,
	    .format = format,
	    .extent = {
	        .width = width,
	        .height = height,
	        .depth = depth,
	    },
	    .mipLevels = 4u,
	    .arrayLayers = 1u,
	    .samples = sample_count,
	    .tiling = tiling,
	    .usage = usage,
	    .sharingMode = ctx.swapchain.sharing_mode,
	    .initialLayout = init_layout,
	};

	vk_check(vk::createImage(ctx.dev.log_dev, &image_ci, ctx.vk_alloc, &out_image.handle));

	out_image.width = width;
	out_image.height = height;
	out_image.depth = depth;
	out_image.type = type;
	out_image.format = format;
	out_image.aspect_flags = aspect_flags;

    VkMemoryRequirements mem_reqs @noinit;
    vk::getImageMemoryRequirements(ctx.dev.log_dev, out_image.handle, &mem_reqs);

	uint mem_type_ind = ctx.dev.find_mem_type_index(mem_reqs.memoryTypeBits, mem_flags)!!;

    VkMemoryAllocateInfo alloc_info = {
        .sType = vk::STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = mem_reqs.size,
        .memoryTypeIndex = mem_type_ind,
    };

    vk_check(vk::allocateMemory(ctx.dev.log_dev, &alloc_info, ctx.vk_alloc, &out_image.memory));
    vk_check(vk::bindImageMemory(ctx.dev.log_dev, out_image.handle, out_image.memory, 0));

    if (should_create_view) {
        out_image.create_view(ctx, aspect_flags);
    }

    return true;
}

fn void VulkanImage.create_view(&image, VulkanContext* ctx, VkImageAspectFlags aspect_flags = vk::IMAGE_ASPECT_COLOR_BIT)
{
	image.view = create_view_from_raw(ctx, image.handle, image.format, (VkImageViewType)image.type, aspect_flags);
}

fn VkImageView create_view_from_raw(
	VulkanContext* ctx,
	VkImage raw_image,
	VkFormat format,
	VkImageViewType type = vk::IMAGE_VIEW_TYPE_2D,
	VkImageAspectFlags aspect_flags = vk::IMAGE_ASPECT_COLOR_BIT,
)
{
    VkImageView view @noinit;

    VkImageViewCreateInfo image_view_ci = {
        .sType = vk::STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .image = raw_image,
        .viewType = type,
        .format = format,
        .subresourceRange = {
            .aspectMask = aspect_flags,
            .baseMipLevel = 0,
            .levelCount = vk::REMAINING_MIP_LEVELS,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    vk_check(vk::createImageView(ctx.dev.log_dev, &image_view_ci, ctx.vk_alloc, &view));
    return view;
}

fn void VulkanImage.cmd_transition_layout(
	&image,
    VulkanCmdBuffer cmd_buffer,
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
		(image.aspect_flags & vk::IMAGE_ASPECT_DEPTH_BIT) > 0,
	);
}

fn void cmd_transition_layout_raw(
    VkImage raw_image,
    VulkanCmdBuffer cmd_buffer,
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
        .sType = vk::STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = src_stage_mask,
        .srcAccessMask = src_access_mask,
        .dstStageMask = dest_stage_mask,
        .dstAccessMask = dest_access_mask,
        .oldLayout = src_layout,
        .newLayout = dest_layout,
        .srcQueueFamilyIndex = vk::QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk::QUEUE_FAMILY_IGNORED,
        .image = raw_image,
        .subresourceRange = {
            .aspectMask = is_depth ? vk::IMAGE_ASPECT_DEPTH_BIT : vk::IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = vk::REMAINING_MIP_LEVELS,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    VkDependencyInfo deps_info = {
        .sType = vk::STRUCTURE_TYPE_DEPENDENCY_INFO,
        .dependencyFlags = 0,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &barrier,
    };

    vk::cmdPipelineBarrier2(cmd_buffer.handle, &deps_info);
}

fn void VulkanImage.destroy(&image, VulkanContext* ctx)
{
	if (image.handle) {
	    vk::destroyImageView(ctx.dev.log_dev, image.view, ctx.vk_alloc);
	    vk::freeMemory(ctx.dev.log_dev, image.memory, ctx.vk_alloc);
	    vk::destroyImage(ctx.dev.log_dev, image.handle, ctx.vk_alloc);
	    image.view = null;
	    image.memory = null;
	    image.handle = null;
	}
}
