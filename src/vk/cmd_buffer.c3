module vk;

import std::collections::elastic_array;
import soa;

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
	VkCommandBuffer      handle;
	VulkanCmdBufferState state;
}

struct VulkanCmdBufferSOA <CAP>
{
	ElasticArray{VkCommandBuffer, FRAMES_IN_FLIGHT}      handles;
	ElasticArray{VulkanCmdBufferState, FRAMES_IN_FLIGHT} states;
}

struct VulkanCmdBufferSOAView
{
	VkCommandBuffer[]      handles;
	VulkanCmdBufferState[] states;
}

<*
	@require cmd_buff.state == VulkanCmdBufferState.READY : "Should be in READY state"
*>
fn void VulkanCmdBuffer.begin_recording(&cmd_buff, VkCommandBufferUsageFlags flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT)
{
    VkCommandBufferBeginInfo begin_info = {
        .s_type = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = flags,
    };
    vk_check(vkBeginCommandBuffer(cmd_buff.handle, &begin_info));
    cmd_buff.state = VulkanCmdBufferState.RECORDING_BEGIN;
}

<*
	@require cmd_buff.state == VulkanCmdBufferState.RECORDING_BEGIN : "Should be in RECORDING_BEGIN state"
*>
fn void VulkanCmdBuffer.end_recording(&cmd_buff)
{
    vk_check(vkEndCommandBuffer(cmd_buff.handle));
    cmd_buff.state = VulkanCmdBufferState.RECORDING_END;
}

<*
	@require cmd_buff.state == VulkanCmdBufferState.SUBMITTED : "Should be in SUBMITTED state"
*>
fn void VulkanCmdBuffer.reset(&cmd_buff, VkCommandBufferResetFlags flags)
{
    vk_check(vkResetCommandBuffer(cmd_buff.handle, flags));
    cmd_buff.state = VulkanCmdBufferState.READY;
}

// Pool
 
struct VulkanCmdPool
{
	VkCommandPool handle;
}

fn void VulkanCmdPool.init(&cmd_pool, VulkanContext* ctx, char queue_fam_ind)
{
    VkCommandPoolCreateInfo cmd_pool_ci = {
        .s_type = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queue_family_index = (uint)queue_fam_ind,
    };
    vk_check(vkCreateCommandPool(ctx.dev.log_dev, &cmd_pool_ci, ctx.vk_alloc, &cmd_pool.handle));
}

<*
	@require out_cmd_buffs.handles.len > 0
*>
fn void VulkanCmdPool.allocate_cmd_buffers(&cmd_pool, VulkanDevice* dev, VulkanCmdBufferSOAView out_cmd_buffs, bool is_primary = true)
{
    VkCommandBufferAllocateInfo alloc_info = {
        .s_type = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .command_pool = cmd_pool.handle,
        .level = is_primary ? VK_COMMAND_BUFFER_LEVEL_PRIMARY : VK_COMMAND_BUFFER_LEVEL_SECONDARY,
        .command_buffer_count = (uint)soa::@len(out_cmd_buffs),
    };

    vk_check(vkAllocateCommandBuffers(dev.log_dev, &alloc_info, out_cmd_buffs.handles.ptr));
	foreach (&state : out_cmd_buffs.states) {
        *state = VulkanCmdBufferState.READY;
    }
}

<*
	@require out_cmd_buffs.handles.len > 0
*>
fn void VulkanCmdPool.free_cmd_buffers(&cmd_pool, VulkanDevice* dev, VulkanCmdBufferSOAView out_cmd_buffs)
{
    vkFreeCommandBuffers(dev.log_dev, cmd_pool.handle, out_cmd_buffs.handles.len, out_cmd_buffs.handles.ptr);
    foreach (&state : out_cmd_buffs.states) {
        *state = VulkanCmdBufferState.NOT_ALLOCATED;
    }
}

fn void VulkanCmdPool.destroy(&cmd_pool, VulkanContext* ctx)
{
	if (cmd_pool.handle) {
	    vkDestroyCommandPool(ctx.dev.log_dev, cmd_pool.handle, ctx.vk_alloc);
		cmd_pool.handle = null;
	}
}
