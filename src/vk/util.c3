module vk;

import logger;

fn void vk_check(vk::VkResult r)
{
    if (r != VK_SUCCESS) {
		$if ($feature(SF_DEBUG)):
            logger::@logn(LogLevel.FATAL, "Vk check failed, result was %d", r);
		$endif
		builtin::abort();
    }
}
