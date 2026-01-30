module vk;

import logger;

// VulkanSemaphore

struct VulkanSemaphore
{
    VkSemaphore handle;
}

fn void VulkanSemaphore.init(&sem, VulkanContext* ctx)
{
    sem.handle = VK_NULL_HANDLE;
    VkSemaphoreCreateInfo semaphore_ci = {
        .s_type = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
    };
    vk_check(vkCreateSemaphore(ctx.dev.log_dev, &semaphore_ci, ctx.vk_alloc, &sem.handle));
}

fn void VulkanSemaphore.destroy(&sem, VulkanContext* ctx)
{
    if (sem.handle) {
        vkDestroySemaphore(ctx.dev.log_dev, sem.handle, ctx.vk_alloc);
        sem.handle = null;
    }
}

// VulkanFence

struct VulkanFence
{
    VkFence handle;
    bool    is_signaled;
}

fn void VulkanFence.init(&fence, VulkanContext* ctx, bool init_singaled = false)
{
    fence.handle = VK_NULL_HANDLE;
	fence.is_signaled = init_singaled;
    VkFenceCreateInfo fence_ci = {
        .s_type = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };
    if (init_singaled) {
        fence_ci.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    }
    vk_check(vkCreateFence(ctx.dev.log_dev, &fence_ci, null, &fence.handle));
}

<*
	@require fence.is_signaled == false
*>
fn bool VulkanFence.wait(&fence, VulkanContext* ctx)
{
    VkResult result = VK_TIMEOUT;

    while (true) {
        result = vkWaitForFences(ctx.dev.log_dev, 1u, &fence.handle, VK_TRUE, ulong.max);
        if (result != VK_TIMEOUT) {
            break;
        }
    }
    
    if (result == VK_SUCCESS) {
        fence.is_signaled = true;
        return true;
    } else {
        logger::@logn(LogLevel.FATAL, "Fence wait error occurred");
        return false;
    }
}

fn void VulkanFence.reset(&fence, VulkanContext* ctx)
{
    if (!fence.is_signaled) {
        return;
    }
    
    vk_check(vkResetFences(ctx.dev.log_dev, 1u, &fence.handle));
    fence.is_signaled = false;
}

fn void VulkanFence.destroy(&fence, VulkanContext* ctx)
{
    if (fence.handle) {
        vkDestroyFence(ctx.dev.log_dev, fence.handle, ctx.vk_alloc);
        fence.handle = null;
    }
}
