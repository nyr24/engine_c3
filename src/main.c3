module game_engine;

import app;

fn int main(String[] args)
{
	if (!app::init()) {
		return -1;
	}

	return 0;
}

module std::core::env;
const GLFW_INCLUDE_VULKAN = true;
