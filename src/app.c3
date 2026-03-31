module engine;

import window;
import vk;
import logger;
import glfw;
import nyr_allocators;

const PERSISTENT_ALLOC_CAPACITY	   = 16384;
const TEMP_ALLOC_CAPACITY          = 8192;
const TEMP_ALLOC_INIT_REGION_COUNT = 2;
const INIT_TEXTURE_COUNT           = 128;

struct AppConfig
{
	String name;
	uint init_width;
	uint init_height;
}

struct App
{
	EventSystem event_sys;
	InputSystem input_sys;
	TextureSystem tex_sys;
	VulkanContext vk_ctx;
	ArenaAlloc temp_alloc;
	BSTAlloc persistent_alloc;
	Window window;
}

fn void? App.init(&app, AppConfig config)
{
	app.persistent_alloc.init(mem, PERSISTENT_ALLOC_CAPACITY, BEST_FIT);
	app.temp_alloc.init(mem, TEMP_ALLOC_CAPACITY, TEMP_ALLOC_CAPACITY, TEMP_ALLOC_INIT_REGION_COUNT);

	Window? window = window::create(app, "engine_window", 800, 600);
	if (catch err = window)
	{
		logger::logn(FATAL, "Failed failed to initialize a window: %s", err);
		return err~;
	}
	app.window = window;
	app.input_sys.init(app);
	app.tex_sys.init(&app.persistent_alloc, INIT_TEXTURE_COUNT);

	if (catch err = vk::init_vk(app, &config, &app.window))
	{
		logger::logn(FATAL, "Failed to initialize vulkan, reason: %s", err);
		return err~;
	}
}

fn void App.run(&app)
{
	app.vk_ctx.renderer.start_clock();

	while (!glfw::windowShouldClose(app.window.handle) && !app.vk_ctx.renderer.should_close())
	{
		glfw::pollEvents();
		SwapchainPresentRes acquire_res = vk::begin_frame(app);
		if (acquire_res != NEEDS_RECREATION_CANT_PROCEED)
		{
			vk::draw_frame(app);
			vk::end_frame(app);
		}
	}
}

fn void App.shutdown(&app)
{
	app.vk_ctx.dev.wait_idle();

	app.tex_sys.destroy();

	app.vk_ctx.destroy();
	app.window.destroy();

	app.persistent_alloc.free();
	app.temp_alloc.free();
}
