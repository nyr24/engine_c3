module vk;

import app;
import window;

struct VkContext {
	Device device;
	VkInstance instance;
	VkSurfaceKHR surface;
	VkDebugUtilsMessengerEXT debug_messenger;
}

faultdef INSTANCE_INIT_FAILED,
	DEVICE_INIT_FAILED,
	LAYERS_INIT_FAILED;

fn void? init_vk(VkContext* out_context, AppConfig* app_config, Window* window)
{
	vk_check(vk::volk_initialize());

	if (!init_instance(out_context, app_config)) {
		return INSTANCE_INIT_FAILED?;
	}

	window.create_vk_surface(out_context.instance, &out_context.surface);

	if (!init_device(out_context)) {
		return DEVICE_INIT_FAILED?;
	}
}
