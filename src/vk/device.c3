module vk;

import std::collections::elastic_array;
import std::collections::list;
import std::collections::set;
import std::collections::maybe;
import std::math;
import util;
import logger;

const MAX_PHYS_DEVS = 10u;
const MAX_FORMATS = 128u;
const MAX_PRESENT_MODES = 8u;
const MAX_DEVICE_REQ_EXT = 10u;
const MAX_DEVICE_AVAIL_EXT = 128u;
const MAX_QUEUE_FAMILIES = 16u;
const MAX_QUEUE_CNT = 4u;

struct Device {
	SwapchainSupportInfo				swapchain_supp_info;
    VkPhysicalDevice                    phys_dev;
    VkDevice                            log_dev;
    VkPhysicalDeviceMemoryProperties    mem_props;
    VkQueue                             graphics_queue;
    VkQueue                             present_queue;
    VkQueue                             transfer_queue;
    VkQueue                             compute_queue;
	QueueIndices						queue_indices;
    VkFormat                            depth_fmt;
}

struct QueueIndex {
	char fam;
	char queue;
}

struct QueueCount {
	char fam_ind;
	char cnt;
}

struct QueueIndices {
	QueueIndex graphics;
	QueueIndex present;
	QueueIndex transfer;
	QueueIndex compute;
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

	ElasticArray{VkPhysicalDevice, MAX_PHYS_DEVS} phys_devs @noinit;
	phys_devs.resize(math::min(MAX_PHYS_DEVS, device_cnt));

	vk_check(vkEnumeratePhysicalDevices(context.instance, &device_cnt, phys_devs.data()));

	ElasticArray{CChar*, MAX_DEVICE_REQ_EXT} device_req_extensions;
	device_req_extensions.push_all({ (CChar*)VK_KHR_SWAPCHAIN_EXTENSION_NAME, (CChar*)VK_KHR_SHADER_DRAW_PARAMETERS_EXTENSION_NAME, (CChar*)VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME });

	VkPhysicalDevice selected_phys_dev = null;
	SwapchainSupportInfo swapchain_supp_info;
	CChar*[] req_ext_view = device_req_extensions.array_view();

	foreach (dev : phys_devs.array_view()) {
		if (is_suitable(dev, context.surface, req_ext_view, &swapchain_supp_info)) {
			selected_phys_dev = dev;
			break;
		}
	}

	if (!selected_phys_dev) {
		logger::@logn(LogLevel.FATAL, "Appropriate device was not found");
		return false;
	}

	context.device.phys_dev = selected_phys_dev;

	if (!context.device.detect_depth_format()) {
		logger::@logn(LogLevel.FATAL, "Suitable depth format was not detected");
		return false;
	}

	vkGetPhysicalDeviceMemoryProperties(selected_phys_dev, &context.device.mem_props);

	// Queue Selection
	ElasticArray{char, MAX_QUEUE_FAMILIES} selected_fam_queue_cnts;
	
	if (!find_queue_families(selected_phys_dev, context.surface, &selected_fam_queue_cnts, &context.device.queue_indices)) {
		logger::@logn(LogLevel.FATAL, "Failed to find required queue families on the device");
		return false;
	}

	ElasticArray{QueueCount, MAX_QUEUE_FAMILIES} compact_queue_fam_cnts @noinit;
	calc_required_queue_counts(selected_fam_queue_cnts.array_view(), &compact_queue_fam_cnts);
	
	ElasticArray{VkDeviceQueueCreateInfo, MAX_QUEUE_FAMILIES} queue_infos @noinit;
	queue_infos.resize(compact_queue_fam_cnts.size);

	ElasticArray{float, MAX_QUEUE_FAMILIES} queue_priorities @noinit;
	queue_priorities.resize(compact_queue_fam_cnts.size);
	queue_priorities.fill(1.0);
	QueueIndex* queue_indices_ptr = (QueueIndex*)&context.device.queue_indices;

	foreach (uint i, &info : queue_infos.array_view()) {
		if (compact_queue_fam_cnts[i].cnt == 0) {
			continue;
		}
	
		info.s_type = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        info.p_next = null;
        info.queue_family_index = compact_queue_fam_cnts[i].fam_ind;
        info.queue_count = compact_queue_fam_cnts[i].cnt;
        info.flags = 0;
        info.p_queue_priorities = &queue_priorities[i];
	}

    VkPhysicalDeviceFeatures device_features = {
        .sampler_anisotropy = VK_TRUE,
    };

    VkPhysicalDeviceVulkan13Features device_features13 = {
        .s_type = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .dynamic_rendering = VK_TRUE,
        .synchronization_2 = VK_TRUE,
    };

    VkPhysicalDeviceVulkan12Features device_features12 = {
        .s_type = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .p_next = &device_features13,
        .buffer_device_address = VK_TRUE,
        .descriptor_indexing = VK_TRUE,
    };

    VkDeviceCreateInfo device_create_info = {
        .s_type = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .p_next = &device_features12,
        .queue_create_info_count = (uint)queue_infos.size,
        .p_queue_create_infos = queue_infos.data(),
        .enabled_extension_count = (uint)device_req_extensions.size,
        .pp_enabled_extension_names = device_req_extensions.data(),
        .p_enabled_features = &device_features,
    };

    vk_check(vkCreateDevice(context.device.phys_dev, &device_create_info, null, &context.device.log_dev));
    volk_load_device(context.device.log_dev);

    vkGetDeviceQueue(context.device.log_dev, context.device.queue_indices.graphics.fam, context.device.queue_indices.graphics.queue, &context.device.transfer_queue);
    vkGetDeviceQueue(context.device.log_dev, context.device.queue_indices.present.fam, context.device.queue_indices.present.queue, &context.device.present_queue);
    vkGetDeviceQueue(context.device.log_dev, context.device.queue_indices.transfer.fam, context.device.queue_indices.transfer.queue, &context.device.transfer_queue);
    vkGetDeviceQueue(context.device.log_dev, context.device.queue_indices.compute.fam, context.device.queue_indices.compute.queue, &context.device.compute_queue);

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
	VkSurfaceKHR surface,
    ElasticArray{char, MAX_QUEUE_FAMILIES}* selected_fam_queue_cnts,
	QueueIndices* out_indices,
) @private
{
	uint queue_fam_cnt @noinit;
    vkGetPhysicalDeviceQueueFamilyProperties(dev, &queue_fam_cnt, null);

    ElasticArray{VkQueueFamilyProperties, MAX_QUEUE_FAMILIES} queue_families;
	queue_fam_cnt = math::min(MAX_QUEUE_FAMILIES, queue_fam_cnt);
	queue_families.resize(queue_fam_cnt);
	selected_fam_queue_cnts.resize(queue_fam_cnt);
    vkGetPhysicalDeviceQueueFamilyProperties(dev, &queue_fam_cnt, queue_families.data());
	
    VkQueueFamilyProperties[] queue_family_slice = queue_families.array_view();
    char[] selected_fam_queue_cnts_slice = selected_fam_queue_cnts.array_view();
	Maybe{char[]} not_needed_fam_indices = maybe::EMPTY;

	{
		Maybe{QueueIndex} maybe_queue_ind = pick_queue(queue_family_slice, selected_fam_queue_cnts_slice, VK_QUEUE_GRAPHICS_BIT, 0, VK_QUEUE_TRANSFER_BIT, 1, not_needed_fam_indices);
	    if (try QueueIndex ind = maybe_queue_ind.get()) {
	        out_indices.graphics = ind;
			selected_fam_queue_cnts_slice[ind.fam]++;
	    } else {
	        logger::@logn(LogLevel.FATAL, "Appropriate queue for Graphics was not found on selected vulkan device");
	        return false;
	    }
	}

    {
        not_needed_fam_indices = maybe::value({ out_indices.graphics.fam });
		Maybe{QueueIndex} maybe_ind = pick_queue(queue_family_slice, selected_fam_queue_cnts_slice, VK_QUEUE_TRANSFER_BIT, 0, VK_QUEUE_GRAPHICS_BIT, 1, not_needed_fam_indices);
	    if (try QueueIndex ind = maybe_ind.get()) {
            out_indices.transfer = ind;
			selected_fam_queue_cnts_slice[ind.fam]++;
        } else {
            out_indices.transfer = out_indices.graphics;
        }
    }

    {
		Maybe{QueueIndex} maybe_ind = pick_presentation_queue(queue_family_slice, selected_fam_queue_cnts_slice, dev, surface, not_needed_fam_indices);
        if (try QueueIndex ind = maybe_ind.get()) {
            out_indices.present = ind;
			selected_fam_queue_cnts_slice[ind.fam]++;
        } else {
            out_indices.present = out_indices.graphics;
        }
    }

    {
		Maybe{QueueIndex} maybe_ind = pick_queue(queue_family_slice, selected_fam_queue_cnts_slice, VK_QUEUE_COMPUTE_BIT, VK_QUEUE_TRANSFER_BIT, VK_QUEUE_GRAPHICS_BIT, 1, not_needed_fam_indices);
        if (try QueueIndex ind = maybe_ind.get()) {
            out_indices.compute = ind;
			selected_fam_queue_cnts_slice[ind.fam]++;
        } else {
			out_indices.compute = out_indices.graphics;
        }
    }

    return true;
}

fn Maybe{QueueIndex} pick_queue(
    VkQueueFamilyProperties[] queue_families,
	char[] selected_fam_queue_cnts,
    VkQueueFlagBits required_flag,
    VkQueueFlagBits optional_flags,
    VkQueueFlagBits not_needed_flags,
    char min_queue_count,
    Maybe{char[]} maybe_not_needed_indices,
)
{
    uint max_score = 0;
    Maybe{QueueIndex} result_index = maybe::EMPTY;
    uint curr_score @noinit;

	foreach (uint i, &family : queue_families) {
        if (((family.queue_flags & required_flag) != required_flag)
			|| (family.queue_count <= selected_fam_queue_cnts[i])
			|| (family.queue_count < min_queue_count))
		{
            continue;
        }

        curr_score = 1;

        if (try char[] not_needed_indices = maybe_not_needed_indices.get()) {
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
            result_index = maybe::value({
				.fam = (char)i,
				.queue = selected_fam_queue_cnts[i],
			});
            max_score = curr_score;
        }
    }

    return result_index;
}

fn Maybe{QueueIndex} pick_presentation_queue(
    VkQueueFamilyProperties[] queue_families,
	char[] selected_fam_queue_cnts,
    VkPhysicalDevice dev,
    VkSurfaceKHR surface,
    Maybe{char[]} maybe_not_needed_indices,
)
{
    uint max_score = 0;
    Maybe{QueueIndex} result_index = maybe::EMPTY;
    uint curr_score @noinit;

	foreach (uint i, &family : queue_families) {
		if (family.queue_count <= selected_fam_queue_cnts[i]) {
			continue;
		}

        uint supports_presentation @noinit;
        vk_check(vkGetPhysicalDeviceSurfaceSupportKHR(dev, i, surface, &supports_presentation));

        if (!supports_presentation) {
            continue;
        }

        curr_score = 1;

        if ((family.queue_flags & VK_QUEUE_GRAPHICS_BIT) > 0) {
            curr_score += 1;
        }

        if (try char[] not_needed_indices = maybe_not_needed_indices.get()) {
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
            result_index = maybe::value({
				.fam = (char)i,
				.queue = selected_fam_queue_cnts[i],
			});
            max_score = curr_score;
        }
    }

    return result_index;
}

fn void calc_required_queue_counts(char[] selected_queue_cnts, ElasticArray{QueueCount, MAX_QUEUE_FAMILIES}* out_queue_counts) {
	foreach (char i, char cnt : selected_queue_cnts) {
		if (cnt == 0) {
			continue;
		}
		out_queue_counts.push({
			.fam_ind = i,
			.cnt = cnt,
		});
	}
}
