module vk;

import std::collections::elastic_array;
import std::collections::list;
import std::collections::maybe;
import std::math;
import util;
import logger;

const MAX_QUEUE_CNT = 4u;
const MAX_PHYS_DEVS = 10u;
const MAX_FORMATS = 128u;
const MAX_PRESENT_MODES = 8u;
const MAX_DEVICE_REQ_EXT = 10u;
const MAX_DEVICE_AVAIL_EXT = 128u;
const MAX_QUEUE_FAMILIES = 16u;

struct Device {
	SwapchainSupportInfo				swapchain_supp_info;
    VkPhysicalDevice                    phys_dev;
    VkDevice                            log_dev;
    VkPhysicalDeviceMemoryProperties    mem_props;
    VkQueue                             graphics_queue;
    VkQueue                             present_queue;
    VkQueue                             transfer_queue;
	QueueFamilyIndices					queue_family_indices;
    VkFormat                            depth_fmt;
}

struct QueueFamilyIndices {
    char graphics;
    char present;
    char transfer;
    char compute;
}

struct SwapchainSupportInfo {
	ElasticArray{VkSurfaceFormatKHR, MAX_FORMATS} 		formats;
	ElasticArray{VkPresentModeKHR, MAX_PRESENT_MODES} 	present_modes;
    VkSurfaceCapabilitiesKHR 							capabilities;
}

fn bool init_device(VkContext* context)
{
	uint device_cnt @noinit;
	vk_check(vkEnumeratePhysicalDevices(context.instance, &device_cnt, null));
	if (!device_cnt) {
		logger::@logn(LogLevel.FATAL, "Available devices were not found");
	    return false;
	}

	ElasticArray{VkPhysicalDevice, MAX_PHYS_DEVS} phys_devs;
	phys_devs.resize(math::min(MAX_PHYS_DEVS, device_cnt));

	vk_check(vkEnumeratePhysicalDevices(context.instance, &device_cnt, phys_devs.data()));

	ElasticArray{CChar*, MAX_DEVICE_REQ_EXT} device_req_extensions;
	device_req_extensions.push_all({ (CChar*)VK_KHR_SWAPCHAIN_EXTENSION_NAME, (CChar*)VK_KHR_SHADER_DRAW_PARAMETERS_EXTENSION_NAME, (CChar*)VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME });

	VkPhysicalDevice selected_device = null;
	SwapchainSupportInfo swapchain_supp_info;
	CChar*[] req_ext_view = device_req_extensions.array_view();

	foreach (dev : phys_devs.array_view()) {
		if (is_suitable(dev, context.surface, req_ext_view, &swapchain_supp_info)) {
			selected_device = dev;
		}
	}

	if (!selected_device) {
		logger::@logn(LogLevel.FATAL, "Appropriate device was not found");
		return false;
	}

	context.device.phys_dev = selected_device;

	if (!context.device.detect_depth_format()) {
		logger::@logn(LogLevel.FATAL, "Suitable depth format was not detected");
		return false;
	}

	// TODO: Create logical device

	return true;
}

fn bool is_suitable(VkPhysicalDevice dev, VkSurfaceKHR surface, CChar*[] req_extensions, SwapchainSupportInfo* out_swapchain_supp) @private
{
	VkPhysicalDeviceProperties dev_props @noinit;
	vkGetPhysicalDeviceProperties(dev, &dev_props);
	if (dev_props.device_type != VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
		logger::@logn(LogLevel.TRACE, "Device is not suitable, not a discrete GPU, skipping...");
		return false;
	}

	query_swapchain_support(dev, surface, out_swapchain_supp);
	if (out_swapchain_supp.present_modes.size == 0) {
		logger::@logn(LogLevel.TRACE, "Physical device is not suitable, doesn't have present modes, skipping...");
		return false;
	}

	List{VkExtensionProperties} avail_extensions;
	
	uint avail_ext_cnt @noinit;
	vk_check(vkEnumerateDeviceExtensionProperties(dev, null, &avail_ext_cnt, null));
	avail_extensions.tinit(avail_ext_cnt);
	avail_extensions.set_size(avail_ext_cnt);
	defer avail_extensions.free();

	// avail_ext_cnt = math::min(avail_ext_cnt, MAX_DEVICE_AVAIL_EXT);
	// avail_extensions.resize(avail_ext_cnt);
	
	vk_check(vkEnumerateDeviceExtensionProperties(dev, null, &avail_ext_cnt, &avail_extensions[0]));

	foreach (req_ext : req_extensions) {
		bool found = false;
		foreach (&avail_ext : avail_extensions.array_view()) {
			if (util::nullterm_str_eq(&avail_ext.extension_name, req_ext)) {
				found = true;
				break;
			}
		}
		if (!found) {
			logger::@logn(LogLevel.INFO, "Required device extension was not found, extension name: %s, skipping...", req_ext);
			return false;
		}
	}

	VkPhysicalDeviceFeatures dev_features @noinit;
	vkGetPhysicalDeviceFeatures(dev, &dev_features);

	if (!dev_features.sampler_anisotropy) {
		logger::@logn(LogLevel.INFO, "Physical device does not have sampler_anisotropy, which is required feature, skipping...");
		return false;
	}

	return true;
}

fn void query_swapchain_support(VkPhysicalDevice dev, VkSurfaceKHR surface, SwapchainSupportInfo* out_swapchain_supp) @private
{
	vk_check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(dev, surface, &out_swapchain_supp.capabilities));

    uint format_cnt @noinit;
    uint present_mode_cnt @noinit;
    vk_check(vkGetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_cnt, null));
    vk_check(vkGetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &present_mode_cnt, null));

    if (format_cnt > 0) {
        out_swapchain_supp.formats.resize(math::min(MAX_FORMATS, format_cnt));
        vk_check(vkGetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_cnt, out_swapchain_supp.formats.data()));
    }

    if (present_mode_cnt > 0) {
        out_swapchain_supp.present_modes.resize(math::min(MAX_PRESENT_MODES, present_mode_cnt));
        vk_check(vkGetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &present_mode_cnt, out_swapchain_supp.present_modes.data()));
    }
}

fn bool Device.detect_depth_format(&self) {
	assert(self.phys_dev, "Should not be null");

    ElasticArray{VkFormat, 3} candidates;
	candidates.push_all(
		{
			VK_FORMAT_D32_SFLOAT,
			VK_FORMAT_D32_SFLOAT_S8_UINT,
			VK_FORMAT_D24_UNORM_S8_UINT,
		}
	);

    CUInt flags = VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;

	foreach (cand : candidates.array_view()) {
        VkFormatProperties properties @noinit;
        vkGetPhysicalDeviceFormatProperties(self.phys_dev, cand, &properties);
        if (((properties.linear_tiling_features & flags) == flags) || ((properties.optimal_tiling_features & flags) == flags)) {
            self.depth_fmt = cand;
            return true;
        }
    }

    return false;
}

fn bool find_queue_families(
	VkPhysicalDevice dev,
	QueueFamilyIndices* out_indices,
	VkSurfaceKHR surface
) @private
{
    uint queue_family_count @noinit;
    vkGetPhysicalDeviceQueueFamilyProperties(dev, &queue_family_count, null);

    ElasticArray{VkQueueFamilyProperties, MAX_QUEUE_FAMILIES} queue_families;
	queue_family_count = math::min(MAX_QUEUE_FAMILIES, queue_family_count);
	queue_families.resize(queue_family_count);
	
    vkGetPhysicalDeviceQueueFamilyProperties(dev, &queue_family_count, queue_families.data());

    VkQueueFamilyProperties[] queue_family_slice = queue_families.array_view();

	Maybe{uint[]} not_needed_indices = maybe::EMPTY;
	{
		Maybe{uint} maybe_ind = pick_queue_family(queue_family_slice, 2, VK_QUEUE_GRAPHICS_BIT, 0, VK_QUEUE_TRANSFER_BIT, not_needed_indices);
	    if (try uint ind = maybe_ind.get()) {
	        out_indices.graphics = (char)ind;
	    } else {
	        logger::@logn(LogLevel.FATAL, "appropriate queue for Graphics was not found on selected vulkan device");
	        return false;
	    }
	}

    {
        not_needed_indices = maybe::value({ out_indices.graphics });
		Maybe{uint} maybe_ind = pick_queue_family(queue_family_slice, 1, VK_QUEUE_TRANSFER_BIT, 0, VK_QUEUE_GRAPHICS_BIT, not_needed_indices);
	    if (try uint ind = maybe_ind.get()) {
            out_indices.transfer = (char)ind;
        } else {
	        logger::@logn(LogLevel.FATAL, "appropriate queue for Transfer was not found on selected vulkan device");
            return false;
        }
    }

    {
        not_needed_indices = maybe::value({ out_indices.graphics, out_indices.transfer });
		Maybe{uint} maybe_ind = pick_queue_family(queue_family_slice, 1, VK_QUEUE_COMPUTE_BIT, VK_QUEUE_GRAPHICS_BIT, VK_QUEUE_TRANSFER_BIT, not_needed_indices);
        if (try uint ind = maybe_ind.get()) {
            out_indices.compute = (char)ind;
        } else {
	        logger::@logn(LogLevel.FATAL, "appropriate queue for Computing was not found on selected vulkan device");
            return false;
        }
    }

    {
        not_needed_indices = maybe::value({ out_indices.transfer, out_indices.compute });
		Maybe{uint} maybe_ind = pick_presentation_queue_family(queue_family_slice, dev, surface, not_needed_indices);
        if (try uint ind = maybe_ind.get()) {
            out_indices.present = (char)ind;
        } else {
            logger::@logn(LogLevel.FATAL, "appropriate queue for Presentation was not found on selected vulkan device");
            return false;
        }
    }

    return true;
}

fn Maybe{uint} pick_queue_family(
    VkQueueFamilyProperties[] queue_families,
    VkQueueFlagBits required_flag,
    VkQueueFlagBits optional_flags,
    VkQueueFlagBits not_needed_flags,
    char min_queue_count,
    Maybe{uint[]} maybe_not_needed_indices,
)
{
    uint max_score = 0;
    Maybe{uint} result_index = maybe::EMPTY;
    uint curr_score @noinit;

	for (uint i = 0; i < queue_families.len; ++i) {
		VkQueueFamilyProperties* family = &queue_families[i];

        if (((family.queue_flags & required_flag) != required_flag) || (family.queue_count < min_queue_count)) {
            continue;
        }

        curr_score = 1;

        if (try uint[] not_needed_indices = maybe_not_needed_indices.get()) {
            bool found = false;
            foreach (index : not_needed_indices) {
                if (i == index) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                curr_score += 1;
            }
        }

        if (optional_flags > 0 && (family.queue_flags & optional_flags) == optional_flags) {
            curr_score += 1;
        }

        if ((family.queue_flags & not_needed_flags) == 0) {
            curr_score += 1;
        }

        if (curr_score > max_score) {
            result_index = maybe::value(i);
            max_score = curr_score;
        }
    }

    return result_index;
}

fn Maybe{uint} pick_presentation_queue_family(
    VkQueueFamilyProperties[] queue_families,
    VkPhysicalDevice dev,
    VkSurfaceKHR surface,
    Maybe{uint[]} maybe_not_needed_indices,
)
{
    uint max_score = 0;
    Maybe{uint} result_index = maybe::EMPTY;
    uint curr_score @noinit;

	for (uint i = 0; i < queue_families.len; ++i) {
		VkQueueFamilyProperties* family = &queue_families[i];

        uint supports_presentation @noinit;
        vk_check(vkGetPhysicalDeviceSurfaceSupportKHR(dev, i, surface, &supports_presentation));

        if (!supports_presentation) {
            continue;
        }

        curr_score = 1;

        if ((family.queue_flags & VK_QUEUE_GRAPHICS_BIT) > 0) {
            curr_score += 1;
        }

        if (try uint[] not_needed_indices = maybe_not_needed_indices.get()) {
            bool found = false;
            foreach (index : not_needed_indices) {
                if (i == index) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                curr_score += 1;
            }
        }

        if (curr_score > max_score) {
            result_index = maybe::value(i);
            max_score = curr_score;
        }
    }

    return result_index;
}
