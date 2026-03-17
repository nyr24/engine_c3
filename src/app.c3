module engine;

import window;
import vk;
import logger;
import glfw;
import arena;

const ARENA_MIN_REGION_SIZE = 4096u;
const ARENA_INIT_REGION_CAPACITY = 16;

struct AppConfig
{
	String name;
	uint   init_width;
	uint   init_height;
}

struct App
{
	EventSystem 	event_sys;
	InputSystem		input_sys;
	VulkanContext 	vk_ctx;
	ArenaAlloc		main_alloc;
	ArenaAlloc		temp_alloc;
	Window			window;
}

fn bool App.init(&app, AppConfig config)
{
	app.main_alloc.init(mem, ARENA_MIN_REGION_SIZE, ARENA_MIN_REGION_SIZE, ARENA_INIT_REGION_CAPACITY);
	app.temp_alloc.init(mem, ARENA_MIN_REGION_SIZE, ARENA_MIN_REGION_SIZE, ARENA_INIT_REGION_CAPACITY);

	Window? window = window::create(app, "engine_window", 800, 600);
	if (catch window) {
		logger::logn(FATAL, "Failed failed to initialize a window");
		return false;
	}
	app.window = window;

	if (catch err = vk::init_vk(app, &config, &app.window)) {
		logger::logn(FATAL, "Failed to initialize vulkan, reason: %s", err);
		return false;
	}

	app.input_sys.init(app);

	return true;
}

fn void App.run(&app)
{
	app.vk_ctx.renderer.start_clock();

	while (!glfw::windowShouldClose(app.window.handle)) {
		glfw::pollEvents();
		SwapchainPresentRes acquire_res = vk::begin_frame(&app.vk_ctx);
		if (acquire_res != NEEDS_RECREATION_CANT_PROCEED) {
			vk::draw_frame(&app.vk_ctx);
			vk::end_frame(&app.vk_ctx);
		}
	}
}

fn void App.shutdown(&app)
{
	app.vk_ctx.dev.wait_idle();
	app.main_alloc.destroy();
	app.temp_alloc.destroy();
	app.vk_ctx.destroy();
	app.window.destroy();
}
