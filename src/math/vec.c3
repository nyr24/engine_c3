module n_math;

alias Vec4 = float[<4>];
alias Vec3 = float[<3>];

struct AxisAngle {	
	Vec3 axis;
	float angle;
}

module n_math {LEN};
alias Vec = float[<LEN>];

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
