module engine::vk;

import vk;
import logger;
import std::collections::elastic_array;
import std::collections::maybe;

// Buffer

enum VulkanCmdBufferState
{
	NOT_ALLOCATED,
	READY,
	RECORDING_BEGIN,
	RECORDING_END,
	SUBMITTED,
}

struct VulkanCmdBuffer
{
	VkCommandBuffer handle;
	VulkanCmdBufferState state;
}

<*
 @require !!handle : "Shouldn't be null handle"
*>
fn void VulkanCmdBuffer.init(&cmd_buff, VkCommandBuffer handle)
{
	cmd_buff.handle = handle;
	cmd_buff.state = READY;
}

<*
 @require cmd_buff.state == VulkanCmdBufferState.READY : "Should be in READY state"
*>
fn void VulkanCmdBuffer.begin_recording(
	&cmd_buff,
	VkCommandBufferUsageFlags flags = vk::COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
)
{
	VkCommandBufferBeginInfo begin_info = { .sType = vk::STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, .flags = flags, };
	check(vk::beginCommandBuffer(cmd_buff.handle, &begin_info));
	cmd_buff.state = RECORDING_BEGIN;
}

<*
 @require cmd_buff.state == VulkanCmdBufferState.RECORDING_BEGIN : "Should be in RECORDING_BEGIN state"
*>
fn void VulkanCmdBuffer.end_recording(&cmd_buff)
{
	check(vk::endCommandBuffer(cmd_buff.handle));
	cmd_buff.state = RECORDING_END;
}

<*
 @require cmd_buff.state == VulkanCmdBufferState.RECORDING_END : "Should be in RECORDING_END state"
*>
fn void VulkanCmdBuffer.submit(
	&cmd_buff,
	VulkanContext* ctx,
	VkQueue queue,
	VkSubmitInfo* submit_info,
	VulkanFence* fence = null,
)
{
	if (!fence)
	{
		check(vk::queueSubmit(queue, 1, submit_info, null));
		cmd_buff.state = SUBMITTED;
	}
	else
	{
		if (fence.is_signaled)
		{
			logger::logn(WARN, "Fence can't be in signaled state when submitting a queue, resetting...");
			fence.reset(ctx);
		}
		check(vk::queueSubmit(queue, 1, submit_info, fence.handle));
		cmd_buff.state = SUBMITTED;
	}
}

<*
 @require cmd_buff.state == VulkanCmdBufferState.SUBMITTED : "Should be in SUBMITTED state"
*>
fn void VulkanCmdBuffer.reset(&cmd_buff, VkCommandBufferResetFlags flags = 0)
{
	check(vk::resetCommandBuffer(cmd_buff.handle, flags));
	cmd_buff.state = READY;
}

fn void cmd_copy_data_between_buff(
	VulkanCmdBuffer cmd_buff,
	VulkanBuffer src,
	VulkanBuffer dst,
	VkBufferCopy* copy_region,
)
{
	vk::cmdCopyBuffer(cmd_buff.handle, src.handle, dst.handle, 1, copy_region);
}

fn void cmd_copy_data_from_buff_to_img(
	VulkanCmdBuffer cmd_buff,
	VulkanBuffer src_buffer,
	VulkanImage* dst_image,
	VkImageLayout dst_image_layout
)
{
	VkBufferImageCopy copy_region = {
		.imageSubresource = {
			.aspectMask = vk::IMAGE_ASPECT_COLOR_BIT,
			.mipLevel = 0,
			.baseArrayLayer = 0,
			.layerCount = 1
		},
		.imageExtent = { .width = dst_image.width, .height = dst_image.height, .depth = dst_image.depth }
	};

	vk::cmdCopyBufferToImage(cmd_buff.handle, src_buffer.handle, dst_image.handle, dst_image_layout, 1, &copy_region);
}

fn void cmd_bind_descriptor_sets(
	VulkanCmdBuffer cmd_buff,
	VulkanPipeline* pipeline,
	VkDescriptorSet[] descriptor_sets,
	uint start_index = 0
)
{
	vk::cmdBindDescriptorSets(
		cmd_buff.handle,
		pipeline.bind_point,
		pipeline.layout,
		start_index,
		descriptor_sets.len,
		descriptor_sets.ptr,
		0,
		null
	);
}

// Pool

struct VulkanCmdPool
{
	VkCommandPool handle;
}

fn void VulkanCmdPool.init(&cmd_pool, VulkanContext* ctx, char queue_fam_ind)
{
	VkCommandPoolCreateInfo cmd_pool_ci = {
		.sType = vk::STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
		.flags = vk::COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
		.queueFamilyIndex = (uint)queue_fam_ind,
	};
	check(vk::createCommandPool(ctx.dev.log_dev, &cmd_pool_ci, ctx.vk_alloc, &cmd_pool.handle));
}

<*
 @require out_cmd_buffs.len > 0 : "Should not be empty array"
*>
fn void VulkanCmdPool.allocate_cmd_buffers(
	&cmd_pool,
	VulkanDevice* dev,
	VkCommandBuffer[] out_cmd_buffs,
	bool is_primary = true
)
{
	VkCommandBufferAllocateInfo alloc_info = {
		.sType = vk::STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
		.commandPool = cmd_pool.handle,
		.level = is_primary ? vk::COMMAND_BUFFER_LEVEL_PRIMARY : vk::COMMAND_BUFFER_LEVEL_SECONDARY,
		.commandBufferCount = out_cmd_buffs.len,
	};
	check(vk::allocateCommandBuffers(dev.log_dev, &alloc_info, out_cmd_buffs.ptr));
}

<*
 @require out_cmd_buffs.len > 0 : "Should not be empty array"
*>
fn void VulkanCmdPool.free_cmd_buffers(&cmd_pool, VulkanDevice* dev, VkCommandBuffer[] out_cmd_buffs)
{
	vk::freeCommandBuffers(dev.log_dev, cmd_pool.handle, out_cmd_buffs.len, out_cmd_buffs.ptr);
}

fn void VulkanCmdPool.destroy(&cmd_pool, VulkanContext* ctx)
{
	if (cmd_pool.handle)
	{
		vk::destroyCommandPool(ctx.dev.log_dev, cmd_pool.handle, ctx.vk_alloc);
		cmd_pool.handle = null;
	}
}
