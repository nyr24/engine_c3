module app;

import window;
import vk;
import logger;

struct AppConfig {
	String name;
	uint init_width;
	uint init_height;
}

const INIT_WND_WIDTH = 800u;
const INIT_WND_HEIGHT = 600u;

fn bool init()
{
	Window? window = window::create("hello", 800, 600);
	if (catch window) {
		logger::@logn(LogLevel.FATAL, "Failed failed to initialize a window");
		return false;
	}
	defer window.destroy();

	VkContext context @noinit;
	AppConfig config = {
		.name = "hello",
		.init_width = INIT_WND_WIDTH,
		.init_height = INIT_WND_HEIGHT,
	};

	if (catch err = vk::init_vk(&context, &config, &window)) {
		// TODO: switch (err)
		logger::@logn(LogLevel.FATAL, "Failed to initialize vulkan");
		return false;
	}

	return true;
}
