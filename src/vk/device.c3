module engine::vk;

import vk;
import util;
import logger;
import std::collections::elastic_array;
import std::collections::list;
import std::collections::maybe;
import std::math;

const MAX_PHYS_DEVS        = 10u;
const MAX_FORMATS          = 128u;
const MAX_PRESENT_MODES    = 8u;
const MAX_DEVICE_REQ_EXT   = 10u;
const MAX_DEVICE_AVAIL_EXT = 128u;
const MAX_QUEUE_FAMILIES   = 16u;
const MAX_QUEUE_CNT        = 4u;
const INVALID_QUEUE_IND    = 255u;

struct VulkanDevice
{
	SwapchainSupportInfo swapchain_supp_info;
	VkPhysicalDevice phys_dev;
	VkDevice log_dev;
	VkPhysicalDeviceMemoryProperties mem_props;
	VkQueue graphics_queue;
	VkQueue present_queue;
	VkQueue transfer_queue;
	VkQueue compute_queue;
	QueueIndices queue_indices;
	VkFormat depth_fmt;
}

struct QueueIndex
{
	char fam;
	char queue;
}

struct QueueCount
{
	char fam_ind;
	char cnt;
}

struct QueueIndices
{
	QueueIndex graphics;
	QueueIndex present;
	QueueIndex transfer;
	QueueIndex compute;
}

struct SwapchainSupportInfo
{
	ElasticArray{VkSurfaceFormatKHR, MAX_FORMATS} formats;
	ElasticArray{VkPresentModeKHR, MAX_PRESENT_MODES} present_modes;
	VkSurfaceCapabilitiesKHR capabilities;
}

faultdef MEM_TYPE_IND_NOT_FOUND;

fn bool init_device(VulkanContext* ctx)
{
	VulkanDevice* dev = &ctx.dev;
	uint device_cnt @noinit;
	check(vk::enumeratePhysicalDevices(ctx.instance, &device_cnt, null));
	if (!device_cnt)
	{
		logger::logn(FATAL, "Available devices were not found");
		return false;
	}

	ElasticArray{VkPhysicalDevice, MAX_PHYS_DEVS} phys_devs @noinit;
	phys_devs.resize(math::min(MAX_PHYS_DEVS, device_cnt));

	check(vk::enumeratePhysicalDevices(ctx.instance, &device_cnt, phys_devs.data()));

	ElasticArray{ZString, MAX_DEVICE_REQ_EXT} device_req_extensions;
	device_req_extensions.push_all(
		{
			(ZString)vk::KHR_SWAPCHAIN_EXTENSION_NAME,
			(ZString)vk::KHR_SHADER_DRAW_PARAMETERS_EXTENSION_NAME,
			(ZString)vk::KHR_DYNAMIC_RENDERING_EXTENSION_NAME
		}
	);

	VkPhysicalDevice selected_phys_dev = null;
	ZString[] req_ext_view = device_req_extensions.view();

	foreach (phys_dev : phys_devs.array_view())
	{
		if (is_suitable(phys_dev, ctx.surface, req_ext_view, &ctx.dev.swapchain_supp_info))
		{
			selected_phys_dev = phys_dev;
			break;
		}
	}

	if (!selected_phys_dev)
	{
		logger::logn(FATAL, "Appropriate device was not found");
		return false;
	}

	dev.phys_dev = selected_phys_dev;

	if (!dev.detect_depth_format())
	{
		logger::logn(FATAL, "Suitable depth format was not detected");
		return false;
	}

	vk::getPhysicalDeviceMemoryProperties(selected_phys_dev, &dev.mem_props);

	// Queue Selection
	ElasticArray{char, MAX_QUEUE_FAMILIES} selected_fam_queue_cnts;

	if (!find_queue_families(selected_phys_dev, ctx.surface, &selected_fam_queue_cnts, &dev.queue_indices))
	{
		logger::logn(FATAL, "Failed to find required queue families on the device");
		return false;
	}

	ElasticArray{QueueCount, MAX_QUEUE_FAMILIES} compact_queue_fam_cnts @noinit;
	calc_required_queue_counts(selected_fam_queue_cnts.array_view(), &compact_queue_fam_cnts);

	ElasticArray{VkDeviceQueueCreateInfo, MAX_QUEUE_FAMILIES} queue_infos @noinit;
	queue_infos.resize(compact_queue_fam_cnts.size);

	ElasticArray{float, MAX_QUEUE_FAMILIES} queue_priorities @noinit;
	queue_priorities.resize(compact_queue_fam_cnts.size);
	queue_priorities.fill(1.0);
	QueueIndex* queue_indices_ptr = (QueueIndex*)&dev.queue_indices;

	foreach (uint i, &info : queue_infos.array_view())
	{
		if (compact_queue_fam_cnts[i].cnt == 0)
		{
			continue;
		}

		info.sType = vk::STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
		info.pNext = null;
		info.queueFamilyIndex = compact_queue_fam_cnts[i].fam_ind;
		info.queueCount = compact_queue_fam_cnts[i].cnt;
		info.flags = 0;
		info.pQueuePriorities = &queue_priorities[i];
	}

	VkPhysicalDeviceFeatures device_features = { .samplerAnisotropy = vk::TRUE, };

	VkPhysicalDeviceVulkan13Features device_features13 = {
		.sType = vk::STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		.dynamicRendering = vk::TRUE,
		.synchronization2 = vk::TRUE,
	};

	VkPhysicalDeviceVulkan12Features device_features12 = {
		.sType = vk::STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		.pNext = &device_features13,
		.bufferDeviceAddress = vk::TRUE,
		.descriptorIndexing = vk::TRUE,
	};

	VkDeviceCreateInfo device_ci = {
		.sType = vk::STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.pNext = &device_features12,
		.queueCreateInfoCount = (uint)queue_infos.size,
		.pQueueCreateInfos = queue_infos.data(),
		.enabledExtensionCount = (uint)device_req_extensions.size,
		.ppEnabledExtensionNames = (CChar**)device_req_extensions.data(),
		.pEnabledFeatures = &device_features,
	};

	check(vk::createDevice(dev.phys_dev, &device_ci, ctx.vk_alloc, &dev.log_dev));
	vk::volkLoadDevice(dev.log_dev);

	vk::getDeviceQueue(
		dev.log_dev,
		dev.queue_indices.graphics.fam,
		dev.queue_indices.graphics.queue,
		&dev.graphics_queue
	);
	vk::getDeviceQueue(dev.log_dev, dev.queue_indices.present.fam, dev.queue_indices.present.queue, &dev.present_queue);
	vk::getDeviceQueue(
		dev.log_dev,
		dev.queue_indices.transfer.fam,
		dev.queue_indices.transfer.queue,
		&dev.transfer_queue
	);
	vk::getDeviceQueue(dev.log_dev, dev.queue_indices.compute.fam, dev.queue_indices.compute.queue, &dev.compute_queue);

	return true;
}


fn uint? VulkanDevice.find_mem_type_index(&dev, uint type_filter, VkMemoryPropertyFlagBits mem_flags)
{
	foreach (uint i, mem_type : dev.mem_props.memoryTypes[:dev.mem_props.memoryTypeCount])
	{
		if (((type_filter & (1 << i)) > 0) && ((mem_type.propertyFlags & mem_flags) == mem_flags))
		{
			return i;
		}
	}
	logger::logn(FATAL, "Failed to find memory type index");
	return MEM_TYPE_IND_NOT_FOUND~;
}

fn void VulkanDevice.wait_idle(&dev)
{
	vk::deviceWaitIdle(dev.log_dev);
}

fn bool VulkanDevice.graphics_matches_transfer_queue(&dev)
{
	return dev.queue_indices.graphics.fam == dev.queue_indices.transfer.fam;
}

fn bool is_suitable(
	VkPhysicalDevice dev,
	VkSurfaceKHR surface,
	ZString[] req_extensions,
	SwapchainSupportInfo* out_swapchain_supp
) @private
{
	VkPhysicalDeviceProperties dev_props @noinit;
	vk::getPhysicalDeviceProperties(dev, &dev_props);
	if (dev_props.deviceType != vk::PHYSICAL_DEVICE_TYPE_DISCRETE_GPU)
	{
		logger::logn(TRACE, "Device is not suitable, not a discrete GPU, skipping...");
		return false;
	}

	query_swapchain_support(dev, surface, out_swapchain_supp);
	if (out_swapchain_supp.present_modes.size == 0)
	{
		logger::logn(TRACE, "Physical device is not suitable, doesn't have present modes, skipping...");
		return false;
	}

	List{VkExtensionProperties} avail_extensions;

	uint avail_ext_cnt @noinit;
	check(vk::enumerateDeviceExtensionProperties(dev, null, &avail_ext_cnt, null));
	avail_extensions.tinit(avail_ext_cnt);
	avail_extensions.resize(avail_ext_cnt);
	defer avail_extensions.free();

	check(vk::enumerateDeviceExtensionProperties(dev, null, &avail_ext_cnt, &avail_extensions[0]));

	foreach (req_ext : req_extensions)
	{
		bool found = false;
		foreach (&avail_ext : avail_extensions.array_view())
		{
			if ((ZString)&avail_ext.extensionName == (ZString)req_ext)
			{
				found = true;
				break;
			}
		}
		if (!found)
		{
			logger::logn(INFO, "Required device extension was not found, extension name: %s, skipping...", req_ext);
			return false;
		}
	}

	VkPhysicalDeviceFeatures dev_features @noinit;
	vk::getPhysicalDeviceFeatures(dev, &dev_features);

	if (!dev_features.samplerAnisotropy)
	{
		logger::logn(INFO, "Physical device does not have sampler_anisotropy, which is required feature, skipping...");
		return false;
	}

	return true;
}

fn void query_swapchain_support(
	VkPhysicalDevice dev,
	VkSurfaceKHR surface,
	SwapchainSupportInfo* out_swapchain_supp
) @private
{
	check(vk::getPhysicalDeviceSurfaceCapabilitiesKHR(dev, surface, &out_swapchain_supp.capabilities));

	uint format_cnt @noinit;
	uint present_mode_cnt @noinit;
	check(vk::getPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_cnt, null));
	check(vk::getPhysicalDeviceSurfacePresentModesKHR(dev, surface, &present_mode_cnt, null));

	if (format_cnt > 0)
	{
		out_swapchain_supp.formats.resize(math::min(MAX_FORMATS, format_cnt));
		check(vk::getPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_cnt, out_swapchain_supp.formats.data()));
	}

	if (present_mode_cnt > 0)
	{
		out_swapchain_supp.present_modes.resize(math::min(MAX_PRESENT_MODES, present_mode_cnt));
		check(
			vk::getPhysicalDeviceSurfacePresentModesKHR(
				dev,
				surface,
				&present_mode_cnt,
				out_swapchain_supp.present_modes.data()
			)
		);
	}
}

<*
 @require !!dev.phys_dev : "Should not be null"
*>
fn bool VulkanDevice.detect_depth_format(&dev)
{
	ElasticArray{VkFormat, 3} candidates;
	candidates.push_all({ vk::FORMAT_D32_SFLOAT, vk::FORMAT_D32_SFLOAT_S8_UINT, vk::FORMAT_D24_UNORM_S8_UINT, });

	CUInt flags = vk::FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;

	foreach (cand : candidates.array_view())
	{
		VkFormatProperties properties @noinit;
		vk::getPhysicalDeviceFormatProperties(dev.phys_dev, cand, &properties);
		if (((properties.linearTilingFeatures & flags) == flags)
			|| ((properties.optimalTilingFeatures & flags) == flags))
		{
			dev.depth_fmt = cand;
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
	vk::getPhysicalDeviceQueueFamilyProperties(dev, &queue_fam_cnt, null);

	ElasticArray{VkQueueFamilyProperties, MAX_QUEUE_FAMILIES} queue_families;
	queue_fam_cnt = math::min(MAX_QUEUE_FAMILIES, queue_fam_cnt);
	queue_families.resize(queue_fam_cnt);
	selected_fam_queue_cnts.resize(queue_fam_cnt);
	vk::getPhysicalDeviceQueueFamilyProperties(dev, &queue_fam_cnt, queue_families.data());

	VkQueueFamilyProperties[] queue_family_slice = queue_families.array_view();
	char[] selected_fam_queue_cnts_slice = selected_fam_queue_cnts.array_view();
	Maybe{char[]} not_needed_fam_indices = maybe::EMPTY;

	{
		Maybe{QueueIndex} maybe_queue_ind = pick_queue(
			queue_family_slice,
			selected_fam_queue_cnts_slice,
			vk::QUEUE_GRAPHICS_BIT,
			0,
			vk::QUEUE_TRANSFER_BIT,
			1,
			not_needed_fam_indices
		);
		if (try QueueIndex ind = maybe_queue_ind.get())
		{
			out_indices.graphics = ind;
			selected_fam_queue_cnts_slice[ind.fam]++;
		}
		else
		{
			logger::logn(FATAL, "Appropriate queue for Graphics was not found on selected vulkan device");
			return false;
		}
	}

	{
		not_needed_fam_indices = maybe::value({ out_indices.graphics.fam });
		Maybe{QueueIndex} maybe_ind = pick_queue(
			queue_family_slice,
			selected_fam_queue_cnts_slice,
			vk::QUEUE_TRANSFER_BIT,
			0,
			vk::QUEUE_GRAPHICS_BIT,
			1,
			not_needed_fam_indices
		);
		if (try QueueIndex ind = maybe_ind.get())
		{
			out_indices.transfer = ind;
			selected_fam_queue_cnts_slice[ind.fam]++;
		}
		else
		{
			out_indices.transfer = out_indices.graphics;
		}
	}

	{
		Maybe{QueueIndex} maybe_ind = pick_queue(
			queue_family_slice,
			selected_fam_queue_cnts_slice,
			vk::QUEUE_COMPUTE_BIT,
			vk::QUEUE_TRANSFER_BIT,
			vk::QUEUE_GRAPHICS_BIT,
			1,
			not_needed_fam_indices
		);
		if (try QueueIndex ind = maybe_ind.get())
		{
			out_indices.compute = ind;
			selected_fam_queue_cnts_slice[ind.fam]++;
		}
		else
		{
			out_indices.compute = out_indices.graphics;
		}
	}

	{
		not_needed_fam_indices = maybe::value({ out_indices.transfer.fam });
		Maybe{QueueIndex} maybe_ind = pick_presentation_queue(
			queue_family_slice,
			selected_fam_queue_cnts_slice,
			dev,
			surface,
			maybe::value(out_indices.graphics),
			not_needed_fam_indices
		);
		if (try QueueIndex ind = maybe_ind.get())
		{
			out_indices.present = ind;
			selected_fam_queue_cnts_slice[ind.fam]++;
		}
		else
		{
			out_indices.present = out_indices.graphics;
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
	Maybe{char[]} mb_not_needed_indices,
) @private
{
	uint max_score = 0;
	Maybe{QueueIndex} result_index = maybe::EMPTY;
	uint curr_score @noinit;

	foreach (uint i, &family : queue_families)
	{
		if (((family.queueFlags & required_flag) != required_flag) || (family.queueCount <= selected_fam_queue_cnts[i])
			|| (family.queueCount < min_queue_count))
		{
			continue;
		}

		curr_score = 1;

		if (try char[] not_needed_indices = mb_not_needed_indices.get())
		{
			bool found = false;
			foreach (index : not_needed_indices)
			{
				if (i == index)
				{
					found = true;
					break;
				}
			}
			if (!found)
			{
				curr_score += 1;
			}
		}

		if (optional_flags > 0 && (family.queueFlags & optional_flags) == optional_flags)
		{
			curr_score += 1;
		}

		if ((family.queueFlags & not_needed_flags) == 0)
		{
			curr_score += 1;
		}

		if (curr_score > max_score)
		{
			result_index = maybe::value({ .fam = (char)i, .queue = selected_fam_queue_cnts[i], });
			max_score = curr_score;
		}
	}

	return result_index;
}

fn Maybe{QueueIndex} pick_presentation_queue(
	VkQueueFamilyProperties[] queue_families,
	char[] selected_fam_queue_cnts,
	VkPhysicalDevice dev,
	VkSurfaceKHR surface, // if user specifically wants to combine presentation queue with graphics
	// it can result in performance benefits,
	// because you don't need to synch Swapchain images between separate queues
	Maybe{QueueIndex} mb_graphics_queue_combine_index,
	Maybe{char[]} mb_not_needed_indices,
) @private
{
	uint max_score = 0;
	Maybe{QueueIndex} result_index = maybe::EMPTY;
	uint curr_score @noinit;
	QueueIndex? graphics_queue_ind = mb_graphics_queue_combine_index.get();

	foreach (uint i, &family : queue_families)
	{
		uint supports_presentation @noinit;
		check(vk::getPhysicalDeviceSurfaceSupportKHR(dev, i, surface, &supports_presentation));

		if (!supports_presentation)
		{
			continue;
		}

		if (try graphics_queue_ind)
		{
			if (graphics_queue_ind.fam == i)
			{
				return maybe::value(graphics_queue_ind);
			}
		}

		curr_score = 1;

		if ((family.queueFlags & vk::QUEUE_GRAPHICS_BIT) > 0)
		{
			curr_score += 1;
		}

		if (try char[] not_needed_indices = mb_not_needed_indices.get())
		{
			bool found = false;
			foreach (index : not_needed_indices)
			{
				if (i == index)
				{
					found = true;
					break;
				}
			}
			if (!found)
			{
				curr_score += 1;
			}
		}

		if (curr_score > max_score)
		{
			result_index = maybe::value({ .fam = (char)i, .queue = selected_fam_queue_cnts[i], });
			max_score = curr_score;
		}
	}

	return result_index;
}

fn void calc_required_queue_counts(
	char[] selected_queue_cnts,
	ElasticArray{QueueCount, MAX_QUEUE_FAMILIES}* out_queue_counts
) @private
{
	foreach (char i, char cnt : selected_queue_cnts)
	{
		if (cnt == 0)
		{
			continue;
		}
		out_queue_counts.push({ .fam_ind = i, .cnt = cnt, });
	}
}

fn void VulkanDevice.destroy(&dev, VulkanContext* ctx)
{
	dev.graphics_queue = null;
	dev.present_queue = null;
	dev.transfer_queue = null;

	if (dev.log_dev)
	{
		vk::destroyDevice(dev.log_dev, ctx.vk_alloc);
		dev.log_dev = null;
	}

	dev.phys_dev = null;

	dev.queue_indices.graphics.fam = INVALID_QUEUE_IND;
	dev.queue_indices.graphics.queue = INVALID_QUEUE_IND;
	dev.queue_indices.present.fam = INVALID_QUEUE_IND;
	dev.queue_indices.present.queue = INVALID_QUEUE_IND;
	dev.queue_indices.transfer.fam = INVALID_QUEUE_IND;
	dev.queue_indices.transfer.queue = INVALID_QUEUE_IND;
	dev.queue_indices.compute.fam = INVALID_QUEUE_IND;
	dev.queue_indices.compute.queue = INVALID_QUEUE_IND;
}
