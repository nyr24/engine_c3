module vk;

import logger;

macro void vk_check(VkResult r)
{
    if (r != VK_SUCCESS) {
		$if ($feature(SF_DEBUG)):
            logger::logn(LogLevel.FATAL, "vk_check failed, result was %d", r);
		$endif
		builtin::abort();
    }
}
