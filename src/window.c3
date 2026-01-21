module window;

import glfw;
import vk;

struct Window {
	glfw::GLFWwindow* handle;
	uint 	width;
	uint 	height;
}

faultdef WINDOW_CREATION_FAILED, VULKAN_NOT_SUPPORTED;

fn Window? create(CChar* name, uint width, uint height) {
	if (!glfw::init()) {
		return WINDOW_CREATION_FAILED~;
	}

    if (!glfw::vulkanSupported()) {
		return VULKAN_NOT_SUPPORTED~;
    }

    glfw::windowHint(glfw::CLIENT_API, glfw::NO_API);

    glfw::GLFWwindow* handle = glfw::createWindow((CInt)width, (CInt)height, name, null, null);
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

fn void Window.create_vk_surface(&self, VkInstance instance, VkSurfaceKHR* surface) {
	glfw::createWindowSurface(instance, self.handle, null, surface);
}

fn void Window.destroy(&self) {
	if (self.handle) {
		glfw::destroyWindow(self.handle);
		self.handle = null;
		glfw::terminate();
	}
}
