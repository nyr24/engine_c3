module engine::vk;

import vk;
import logger;

macro void vk_check(VkResult r)
{
    if (r != vk::SUCCESS) {
		$if ($feature(SF_DEBUG)):
            logger::logn(FATAL, "vk_check failed, result was %d", r);
		$endif
		builtin::abort();
    }
}
