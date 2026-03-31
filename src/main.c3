module engine;

const INIT_WND_WIDTH = 800u;
const INIT_WND_HEIGHT = 600u;

fn int main(String[] args)
{
	AppConfig config = {
		.name = "hello",
		.init_width = INIT_WND_WIDTH,
		.init_height = INIT_WND_HEIGHT,
	};

	App app;
	app.init(config)!!;
	defer app.shutdown();

	app.run();
	
	return 0;
}

module std::core::env;
const GLFW_INCLUDE_VULKAN = true;
