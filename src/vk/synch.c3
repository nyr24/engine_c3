module engine::vk;

import vk;
import logger;

faultdef FENCE_WAIT_ERROR;

// VulkanSemaphore

struct VulkanSemaphore
{
    VkSemaphore handle;
}

fn void VulkanSemaphore.init(&sem, VulkanContext* ctx)
{
    sem.handle = (VkSemaphore)null;
    VkSemaphoreCreateInfo semaphore_ci = {
        .sType = vk::STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
    };
    vk_check(vk::createSemaphore(ctx.dev.log_dev, &semaphore_ci, ctx.vk_alloc, &sem.handle));
}

fn void VulkanSemaphore.destroy(&sem, VulkanContext* ctx)
{
    if (sem.handle) {
        vk::destroySemaphore(ctx.dev.log_dev, sem.handle, ctx.vk_alloc);
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
    fence.handle = (VkFence)null;
	fence.is_signaled = init_singaled;
    VkFenceCreateInfo fence_ci = {
        .sType = vk::STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };
    if (init_singaled) {
        fence_ci.flags = vk::FENCE_CREATE_SIGNALED_BIT;
    }
    vk_check(vk::createFence(ctx.dev.log_dev, &fence_ci, null, &fence.handle));
}

<*
	@require fence.is_signaled == false
*>
fn void? VulkanFence.wait(&fence, VulkanContext* ctx)
{
    VkResult result = vk::TIMEOUT;

    while (true) {
        result = vk::waitForFences(ctx.dev.log_dev, 1u, &fence.handle, vk::TRUE, ulong.max);
        if (result != vk::TIMEOUT) {
            break;
        }
    }
    
    if (result == vk::SUCCESS) {
        fence.is_signaled = true;
    } else {
        logger::logn(ERROR, "Fence wait error occurred");
        return FENCE_WAIT_ERROR~;
    }
}

fn void VulkanFence.reset(&fence, VulkanContext* ctx)
{
    if (!fence.is_signaled) {
        return;
    }
    
    vk_check(vk::resetFences(ctx.dev.log_dev, 1u, &fence.handle));
    fence.is_signaled = false;
}

fn void VulkanFence.destroy(&fence, VulkanContext* ctx)
{
    if (fence.handle) {
        vk::destroyFence(ctx.dev.log_dev, fence.handle, ctx.vk_alloc);
        fence.handle = null;
    }
}
