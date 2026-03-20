module engine::vk;

import vk;
import platform;
import logger;
import util;
import std::collections::elastic_array;
import std::core::builtin;
import std::math;

const MAX_REQ_EXT_CNT = 10u;
const MAX_AVAIL_EXT_CNT = 100u;
const MAX_REQ_LAYERS_CNT = 10u;
const MAX_AVAIL_LAYERS_CNT = 30u;

fn bool init_instance(VulkanContext* context, AppConfig* config) @private
{
	context.vk_alloc = null;

    VkApplicationInfo vk_app_info = {
        .sType = vk::STRUCTURE_TYPE_APPLICATION_INFO,
        .apiVersion = vk::API_VERSION_1_3,
    };

    VkInstanceCreateInfo instance_ci = {
        .sType = vk::STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &vk_app_info,
    };

$if ($feature(SF_DEBUG)):
    ElasticArray{ZString, MAX_REQ_LAYERS_CNT} req_layers;
	req_layers.push("VK_LAYER_KHRONOS_validation");

	if (!add_layers(&req_layers))
	{
		return false;
	}
$endif

    ElasticArray{ZString, MAX_REQ_EXT_CNT} req_extensions;
    req_extensions.push((ZString)vk::KHR_SURFACE_EXTENSION_NAME);
    req_extensions.push(platform::get_surface_ext());

$if ($feature(SF_DEBUG)):
	req_extensions.push((ZString)vk::EXT_DEBUG_UTILS_EXTENSION_NAME);
$endif

$if ($feature(SF_DEBUG)):
	if (!check_req_extensions(&req_extensions)) {
		return false;
	}
$endif

	instance_ci.enabledExtensionCount = (uint)req_extensions.size;
	instance_ci.ppEnabledExtensionNames = (CChar**)req_extensions.data();

	vk_check(vk::createInstance(&instance_ci, null, &context.instance));

	vk::volkLoadInstanceOnly(context.instance);

$if ($feature(SF_DEBUG)):
	create_debugger(context);
$endif
	
    return true;
}

fn bool add_layers(ElasticArray{ZString, MAX_REQ_LAYERS_CNT}* req_layers) @if($feature(SF_DEBUG)) @private
{
    ElasticArray{VkLayerProperties, MAX_AVAIL_LAYERS_CNT} avail_layers;
	uint avail_layer_cnt @noinit;

	vk_check(vk::enumerateInstanceLayerProperties(&avail_layer_cnt, null));
	avail_layer_cnt = math::min(MAX_AVAIL_LAYERS_CNT, avail_layer_cnt);
	avail_layers.resize(avail_layer_cnt);
	vk_check(vk::enumerateInstanceLayerProperties(&avail_layer_cnt, avail_layers.data()));

	foreach OUTER: (req_layer : req_layers.array_view()) {
		foreach (&avail_layer : avail_layers.array_view()) {
			if ((ZString)&avail_layer.layerName, req_layer) {
				logger::logn(INFO, "Required layer was found: %s", req_layer);
				continue OUTER;
			}
		}
		logger::logn(FATAL, "Required layer wasn't found: %s\nexiting", req_layer);
		return false;
	}

	return true;
}

fn bool check_req_extensions(ElasticArray{ZString, MAX_REQ_EXT_CNT}* req_extensions) @if($feature(SF_DEBUG)) @private
{
    ElasticArray{VkExtensionProperties, MAX_AVAIL_LAYERS_CNT} avail_extensions;

	uint avail_ext_cnt @noinit;
	vk_check(vk::enumerateInstanceExtensionProperties(null, &avail_ext_cnt, null));
	avail_ext_cnt = math::min(MAX_AVAIL_EXT_CNT, avail_ext_cnt);
	avail_extensions.resize(avail_ext_cnt);

	vk_check(vk::enumerateInstanceExtensionProperties(null, &avail_ext_cnt, avail_extensions.data()));

	foreach OUTER: (req_ext : req_extensions.array_view()) {
		foreach (&avail_ext : avail_extensions.array_view()) {
			if ((ZString)&avail_ext.extensionName == req_ext) {
				continue OUTER;
			}
		}
		logger::logn(FATAL, "Required extension wasn't found: %s\nexiting", req_ext);
		return false;
	}

	return true;
}

fn void create_debugger(VulkanContext* context) @if($feature(SF_DEBUG)) @private
{
    uint log_severity = vk::DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT |
                        vk::DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                        vk::DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
                        vk::DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT;

    VkDebugUtilsMessengerCreateInfoEXT debug_create_info = {
        .sType = vk::STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = log_severity,
        .messageType = vk::DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | vk::DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT | vk::DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT,
        .pfnUserCallback = &vk_debug_callback,
    };

	PFN_vkCreateDebugUtilsMessengerEXT create_debug_messenger =
		(PFN_vkCreateDebugUtilsMessengerEXT)vk::getInstanceProcAddr(context.instance, "vkCreateDebugUtilsMessengerEXT");

	assert(create_debug_messenger != null, "Debug utils extension was not found");

	vk_check(create_debug_messenger(context.instance, &debug_create_info, null, &context.debug_messenger));
}

fn VkBool32 vk_debug_callback(
	VkDebugUtilsMessageSeverityFlagBitsEXT	message_severity,
	VkDebugUtilsMessageTypeFlagsEXT       	message_types,
	VkDebugUtilsMessengerCallbackDataEXT*	callback_data,
	void*                                 	user_data
) @if ($feature(SF_DEBUG)) @export
{
	switch (message_severity) {
	    case vk::DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT:
	        logger::logn(ERROR, "%s", (ZString)callback_data.pMessage);
	        break;
	    case vk::DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT:
	        logger::logn(WARN, "%s", (ZString)callback_data.pMessage);
	        break;
	    case vk::DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT:
	        logger::logn(INFO, "%s", (ZString)callback_data.pMessage);
	        break;
	    case vk::DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT:
	        logger::logn(TRACE, "%s", (ZString)callback_data.pMessage);
	        break;
		default: return vk::FALSE;
	}
	return vk::FALSE;
}
