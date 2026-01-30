module app;

import window;
import vk;
import logger;
import event;
import arena;

const ARENA_MIN_REGION_SIZE = 4096u;
const TEMP_ALLOCATOR_CAPACITY = 4096u * 16u;

struct AppConfig
{
	String name;
	uint   init_width;
	uint   init_height;
}

struct App
{
	EventSystem 	event_sys;
	VulkanContext 	vk_ctx;
	ArenaAlloc		main_alloc;
	Allocator		temp_alloc;
	Window			window;
}

fn bool App.init(&app, AppConfig config)
{
	app.main_alloc.init(mem, 10, ARENA_MIN_REGION_SIZE, ARENA_MIN_REGION_SIZE);
	app.temp_alloc = allocator::new_temp_allocator(mem, TEMP_ALLOCATOR_CAPACITY)!!;

	Window? window = window::create("hello", 800, 600);
	if (catch window) {
		logger::@logn(LogLevel.FATAL, "Failed failed to initialize a window");
		return false;
	}
	app.window = window;

	if (catch err = vk::init_vk(app, &config, &app.window)) {
		logger::@logn(LogLevel.FATAL, "Failed to initialize vulkan, reason: %s", err);
		return false;
	}

	return true;
}

fn void App.shutdown(&app)
{
	app.main_alloc.destroy();
	((TempAllocator*)app.temp_alloc).free();
	app.vk_ctx.destroy();
	app.window.destroy();
}
