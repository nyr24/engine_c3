module engine;

import vk;
import std::math;

struct Vertex
{
	Vec3 pos;
    Vec3 normal;
    Vec2 texture_coord;
}

struct GeometryView {
    uint indices_offset;
    uint indices_count;
    uint vertices_offset;
}

fn void GeometryView.init(&view, uint indices_offset, uint indices_count, uint vertices_offset)
{
	view.indices_offset  = indices_offset;
	view.indices_count   = indices_count;
	view.vertices_offset = vertices_offset;
}

// ---- Cube geometry ----

const CUBE_VERT_COUNT = 24;
const CUBE_INDEX_COUNT = 36;

// Positions
const Vec3 POS_TLN = {-0.5f, -0.5f, +0.0f};
const Vec3 POS_TLF = {-0.5f, -0.5f, -1.0f};
const Vec3 POS_TRN = {+0.5f, -0.5f, +0.0f};
const Vec3 POS_TRF = {+0.5f, -0.5f, -1.0f};
const Vec3 POS_BLN = {-0.5f, +0.5f, +0.0f};
const Vec3 POS_BLF = {-0.5f, +0.5f, -1.0f};
const Vec3 POS_BRN = {+0.5f, +0.5f, +0.0f};
const Vec3 POS_BRF = {+0.5f, +0.5f, -1.0f};

// Texture positions
const Vec2 TEX_COORD_TL = {+0.0f, +1.0f};
const Vec2 TEX_COORD_TR = {+1.0f, +1.0f};
const Vec2 TEX_COORD_BL = {+0.0f, +0.0f};
const Vec2 TEX_COORD_BR = {+1.0f, +0.0f};

// Normals
const Vec3 NORMAL_UP       = {+0.0f, +1.0f, +0.0f};
const Vec3 NORMAL_DOWN     = {+0.0f, -1.0f, +0.0f};
const Vec3 NORMAL_RIGHT    = {+1.0f, +0.0f, +0.0f};
const Vec3 NORMAL_LEFT     = {-1.0f, +0.0f, +0.0f};
const Vec3 NORMAL_FORWARD  = {+0.0f, +0.0f, +1.0f};
const Vec3 NORMAL_BACKWARD = {+0.0f, +0.0f, -1.0f};

macro get_cube_vertices() @const
{
    Vertex[CUBE_VERT_COUNT] $cube_vertices = {
		// front
		{ POS_TLN, NORMAL_FORWARD, TEX_COORD_TL },
		{ POS_BLN, NORMAL_FORWARD, TEX_COORD_BL },
		{ POS_BRN, NORMAL_FORWARD, TEX_COORD_BR },
		{ POS_TRN, NORMAL_FORWARD, TEX_COORD_TR },

		// back
		{ POS_TLF, NORMAL_BACKWARD, TEX_COORD_TL },
		{ POS_BLF, NORMAL_BACKWARD, TEX_COORD_BL },
		{ POS_BRF, NORMAL_BACKWARD, TEX_COORD_BR },
		{ POS_TRF, NORMAL_BACKWARD, TEX_COORD_TR },

		// top
		{ POS_TLN, NORMAL_UP, TEX_COORD_TL },
		{ POS_TRN, NORMAL_UP, TEX_COORD_TR },
		{ POS_TLF, NORMAL_UP, TEX_COORD_BL },
		{ POS_TRF, NORMAL_UP, TEX_COORD_BR },

		// bottom
		{ POS_BLN, NORMAL_DOWN, TEX_COORD_TL },
		{ POS_BRN, NORMAL_DOWN, TEX_COORD_TR },
		{ POS_BLF, NORMAL_DOWN, TEX_COORD_BL },
		{ POS_BRF, NORMAL_DOWN, TEX_COORD_BR },

		// right
		{ POS_TRN, NORMAL_RIGHT, TEX_COORD_TL },
		{ POS_BRN, NORMAL_RIGHT, TEX_COORD_BL },
		{ POS_TRF, NORMAL_RIGHT, TEX_COORD_TR },
		{ POS_BRF, NORMAL_RIGHT, TEX_COORD_BR },

		// left
		{ POS_TLN, NORMAL_LEFT, TEX_COORD_TL },
		{ POS_BLN, NORMAL_LEFT, TEX_COORD_BL },
		{ POS_TLF, NORMAL_LEFT, TEX_COORD_TR },
		{ POS_BLF, NORMAL_LEFT, TEX_COORD_BR },
	};

	return $cube_vertices;
}

<*
 @require $IndexType::kind == UNSIGNED_INT : "Should be unsigned int"
*>
macro get_cube_indices($IndexType) @const
{	
 	$IndexType[CUBE_INDEX_COUNT] $indices = {
		0, 1, 2,        0, 2, 3,
		4, 6, 5,        4, 7, 6,
		8, 9, 10,       9, 11, 10,
		12, 14, 13,     13, 14, 15,
		16, 17, 18,     17, 19, 18,
		20, 22, 21,     21, 22, 23
	};
	return $indices;
}
