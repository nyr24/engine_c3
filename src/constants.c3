module constants;

import vk;

alias ColorRGB = float[3];
alias ColorRGBA = float[4];

const ColorRGB COLOR_WHITE_RGB  = {1.0f, 1.0f, 1.0f};
const ColorRGB COLOR_BLACK_RGB  = {0.0f, 0.0f, 0.0f};
const ColorRGB COLOR_RED_RGB    = {1.0f, 0.0f, 0.0f};
const ColorRGB COLOR_GREEN_RGB  = {0.0f, 1.0f, 0.0f};
const ColorRGB COLOR_BLUE_RGB   = {0.0f, 0.0f, 1.0f};
const ColorRGB COLOR_ORANGE_RGB = {0.0f, 0.5f, 0.1f};
const ColorRGB COLOR_PURPLE_RGB = {0.5f, 0.0f, 0.5f};
const ColorRGB COLOR_YELLOW_RGB = {0.0f, 1.0f, 0.0f};

const ColorRGBA COLOR_WHITE_RGBA      = {1.0f, 1.0f, 1.0f, 1.0f};
const ColorRGBA COLOR_BLACK_RGBA      = {0.0f, 0.0f, 0.0f, 1.0f};
const ColorRGBA COLOR_RED_RGBA        = {1.0f, 0.0f, 0.0f, 1.0f};
const ColorRGBA COLOR_GREEN_RGBA      = {0.0f, 1.0f, 0.0f, 1.0f};
const ColorRGBA COLOR_BLUE_RGBA       = {0.0f, 0.0f, 1.0f, 1.0f};
const ColorRGBA COLOR_ORANGE_RGBA     = {0.0f, 0.5f, 0.1f, 1.0f};
const ColorRGBA COLOR_PURPLE_RGBA     = {0.5f, 0.0f, 0.5f, 1.0f};
const ColorRGBA COLOR_YELLOW_RGBA     = {0.0f, 1.0f, 0.0f, 1.0f};
const ColorRGBA COLOR_DARK_BLUE_RGBA  = {0.0f, 0.0f, 0.15f, 1.0f};

const VkClearValue CLEAR_DEPTH_VALUE = {
	.color = { .float_32 = COLOR_WHITE_RGBA },
	.depth_stencil = {},
};

const VkOffset2D OFFSET_START = { 0, 0 };

const FRAMES_IN_FLIGHT = 2;
const String BUILD_PATH = $feature(SF_DEBUG) ? "build/debug/" : "build/release/";
const String SHADER_PATH = BUILD_PATH +++ "shaders/";
const String TEXTURE_PATH = BUILD_PATH +++ "textures/";
const String VERTEX_SHADER_ENTRY_NAME = "vertMain";
const String FRAGMENT_SHADER_ENTRY_NAME = "fragMain";
const String COMPUTE_SHADER_ENTRY_NAME = "compMain";
const String GEOMETRY_SHADER_ENTRY_NAME = "geoMain";
const String TESSELATION_CONTROL_SHADER_ENTRY_NAME = "tesControlMain";
const String TESSELATION_EVAL_SHADER_ENTRY_NAME = "tesEvalMain";
