module std::math;

alias Vec4 = float[4];
alias Vec3 = float[3];
alias Vec2 = float[2];

alias SimdVec4 = float[<4>];
alias SimdVec3 = float[<3>];
alias SimdVec2 = float[<2>];

struct AxisAngle {	
	Vec3  axis;
	float angle;
}

const Vec3 V3_RIGHT = { 1, 0, 0 };
const Vec3 V3_LEFT = { -1, 0, 0 };
const Vec3 V3_TOP = { 0, 1, 0 };
const Vec3 V3_BOTTOM = { 0, -1, 0 };
const Vec3 V3_FAR = { 0, 0, -1 };
const Vec3 V3_NEAR = { 0, 0, 1 };

const Vec4 V4_RIGHT = { 1, 0, 0, 1 };
const Vec4 V4_LEFT = { -1, 0, 0, 1 };
const Vec4 V4_TOP = { 0, 1, 0, 1 };
const Vec4 V4_BOTTOM = { 0, -1, 0, 1 };
const Vec4 V4_FAR = { 0, 0, -1, 1 };
const Vec4 V4_NEAR = { 0, 0, 1, 1 };
