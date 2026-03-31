module window;

import engine;
import glfw;
import vk;

struct Window
{
	GLFWwindow* handle;
	uint width;
	uint height;
}

faultdef WINDOW_CREATION_FAILED, VULKAN_NOT_SUPPORTED;

fn Window? create(App* app_ctx, ZString name, uint width, uint height)
{
	if (!glfw::init())
	{
		return WINDOW_CREATION_FAILED~;
	}

	if (!glfw::vulkanSupported())
	{
		return VULKAN_NOT_SUPPORTED~;
	}

	glfw::windowHint(glfw::CLIENT_API, glfw::NO_API);

	glfw::GLFWwindow* handle = glfw::createWindow(
		(int)width,
		(int)height,
		name,
		null,
		null
	);

	if (!handle)
	{
		return WINDOW_CREATION_FAILED~;
	}

	Window window = { .handle = handle, .width = width, .height = height };

	glfw::setWindowUserPointer(window.handle, app_ctx);
	glfw::setCursorPosCallback(window.handle, &glfw_mouse_move_callback);
	glfw::setMouseButtonCallback(window.handle, &glfw_mouse_btn_callback);
	glfw::setKeyCallback(window.handle, &glfw_key_callback);
	glfw::setScrollCallback(window.handle, &glfw_mouse_wheel_callback);

	$if $feature(SF_HIDE_CURSOR):
		glfw::setInputMode(window.handle, glfw::CURSOR, glfw::CURSOR_DISABLED);
	$endif

	return window;
}

fn void glfw_mouse_move_callback(GLFWwindow* window, double x, double y)
{
	App* app_ctx = (App*)glfw::getWindowUserPointer(window);
	MousePos pos @noinit;
	pos.x = (float)x;
	pos.y = (float)y;
	app_ctx.input_sys.process_mouse_move(pos);
}

<*
 @require action >= 0 && action <= 1 : "Action should be PRESS or RELEASE, so it converts to EventCode"
*>
fn void glfw_mouse_btn_callback(
	GLFWwindow* window,
	int btn,
	int action,
	int mods
)
{
	App* app_ctx = (App*)glfw::getWindowUserPointer(window);
	app_ctx.input_sys.process_mouse_button(
		(MouseButton)btn,
		action == glfw::PRESS
	);
}

fn void glfw_key_callback(
	GLFWwindow* window,
	int key,
	int scancode,
	int action,
	int mode
)
{
	// We're handling repeat outselves.
	if (action == glfw::REPEAT)
	{
		return;
	}

	App* app_ctx = (App*)glfw::getWindowUserPointer(window);
	app_ctx.input_sys.process_key((uint)key, action == glfw::PRESS);
}

fn void glfw_mouse_wheel_callback(
	GLFWwindow* window,
	double xoffset,
	double yoffset
)
{
	App* app_ctx = (App*)glfw::getWindowUserPointer(window);
	app_ctx.input_sys.process_mouse_wheel(yoffset < 0);
}

<*
 @ensure surface != null : "Shouldn't be null pointer after call"
*>
fn void Window.create_vk_surface(
	&window,
	VkInstance instance,
	VkSurfaceKHR* surface
)
{
	glfw::createWindowSurface(instance, window.handle, null, surface);
}

<*
 @return "Retrieved window coordinates"
*>
fn VkExtent2D Window.get_screen_coordinates(&window)
{
	VkExtent2D coords @noinit;
	glfw::getFramebufferSize(
		window.handle,
		(int*)&coords.width,
		(int*)&coords.height
	);
	return coords;
}

fn void Window.destroy(&window)
{
	if (window.handle)
	{
		glfw::destroyWindow(window.handle);
		window.handle = null;
		glfw::terminate();
	}
}
