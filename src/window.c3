module window;

import glfw;
import vk;

struct Window {
	glfw::GLFWwindow* handle;
	uint 	width;
	uint 	height;
}

faultdef WINDOW_CREATION_FAILED, VULKAN_NOT_SUPPORTED;

fn Window? create(ZString name, uint width, uint height) {
	if (!glfw::init()) {
		return WINDOW_CREATION_FAILED~;
	}

    if (!glfw::vulkanSupported()) {
		return VULKAN_NOT_SUPPORTED~;
    }

    glfw::windowHint(glfw::CLIENT_API, glfw::NO_API);

    glfw::GLFWwindow* handle = glfw::createWindow((CInt)width, (CInt)height, (CChar*)name, null, null);
    if (!handle) {
        return WINDOW_CREATION_FAILED~;
    }

	Window window = { .handle = handle, .width = width, .height = height };

    // out_state.attach_event_callbacks();

    // SF_ASSERT_MSG(out_state.key_callback && out_state.mouse_move_callback && out_state.mouse_btn_callback && out_state.mouse_wheel_callback, "Callbacks should be set");

    // glfwSetKeyCallback(out_state.window, out_state.key_callback);
    // glfwSetMouseButtonCallback(out_state.window, out_state.mouse_btn_callback);
    // glfwSetCursorPosCallback(out_state.window, out_state.mouse_move_callback);
    // glfwSetScrollCallback(out_state.window, out_state.mouse_wheel_callback);
    // glfwSetInputMode(out_state.window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);

    return window;
}

fn void Window.create_vk_surface(&window, VkInstance instance, VkSurfaceKHR* surface) {
	glfw::createWindowSurface(instance, window.handle, null, surface);
}

<*
	@param [out] out_coords : "Retrieved window coordinates"
*>
fn void Window.get_screen_coordinates(&window, VkExtent2D* out_coords)
{
	glfw::getFramebufferSize(window, (CInt*)&out_coords.width, (CInt*)&out_coords.height);
}

fn void Window.destroy(&window) {
	if (window.handle) {
		glfw::destroyWindow(window.handle);
		window.handle = null;
		glfw::terminate();
	}
}
