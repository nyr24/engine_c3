module engine;

import std::io;
import std::math;

const M4_LEN = 16;
const M4_ROWS = 4;
const M4_COLS = 4;
const M3_LEN = 9;
const M3_ROWS = 3;
const M3_COLS = 3;

// NOTE: article reference https://www.kdab.com/projection-matrices-with-vulkan-part-2/

// fn Mat4 perspective_my(float fovy, float aspect, float z_near, float z_far)
// {
// 	float tan_half_fovy = math::tan(fovy / 2);
// 	float fn_scale = 1 / (z_near - z_far);

// 	return (Matrix4x4) {
// 		.m = {
// 			[0] = 1 / (aspect * tan_half_fovy),
// 			[5] = 1 / (tan_half_fovy),
// 			[10] = z_far * fn_scale,
// 			[11] = -1,
// 			[14] = z_far * z_near * fn_scale,
// 		}
// 	};
// }

// GLM version
// fn Mat4 perspective_glm(float fovy, float aspect, float zNear, float zFar)
// {
// 	float tanHalfFovy = math::tan(fovy / 2);
// 	Mat4 res;

// 	res.m00 = 1 / (aspect * tanHalfFovy);
// 	res.m11 = 1 / (tanHalfFovy);
// 	res.m22 = zFar / (zNear - zFar);
// 	res.m32 = -1;
// 	res.m23 = (zFar * zNear) / (zNear - zFar);

// 	return res;
// }


// ------- All glm matrices -------->


/* used by Snowflake engine:
template<typename T>
GLM_FUNC_QUALIFIER mat<4, 4, T, defaultp> perspectiveRH_ZO(T fovy, T aspect, T zNear, T zFar)
{
	assert(abs(aspect - std::numeric_limits<T>::epsilon()) > static_cast<T>(0));

	T const tanHalfFovy = tan(fovy / static_cast<T>(2));

	mat<4, 4, T, defaultp> Result(static_cast<T>(0));
	Result[0][0] = static_cast<T>(1) / (aspect * tanHalfFovy);
	Result[1][1] = static_cast<T>(1) / (tanHalfFovy);
	Result[2][2] = zFar / (zNear - zFar);
	Result[2][3] = - static_cast<T>(1);
	Result[3][2] = -(zFar * zNear) / (zFar - zNear);
	return Result;
}

template<typename T>
GLM_FUNC_QUALIFIER mat<4, 4, T, defaultp> perspectiveLH_ZO(T fovy, T aspect, T zNear, T zFar)
{
	assert(abs(aspect - std::numeric_limits<T>::epsilon()) > static_cast<T>(0));

	T const tanHalfFovy = tan(fovy / static_cast<T>(2));

	mat<4, 4, T, defaultp> Result(static_cast<T>(0));
	Result[0][0] = static_cast<T>(1) / (aspect * tanHalfFovy);
	Result[1][1] = static_cast<T>(1) / (tanHalfFovy);
	Result[2][2] = zFar / (zFar - zNear);
	Result[2][3] = static_cast<T>(1);
	Result[3][2] = -(zFar * zNear) / (zFar - zNear);
	return Result;
}

template<typename T>
GLM_FUNC_QUALIFIER mat<4, 4, T, defaultp> perspectiveRH_NO(T fovy, T aspect, T zNear, T zFar)
{
	assert(abs(aspect - std::numeric_limits<T>::epsilon()) > static_cast<T>(0));

	T const tanHalfFovy = tan(fovy / static_cast<T>(2));

	mat<4, 4, T, defaultp> Result(static_cast<T>(0));
	Result[0][0] = static_cast<T>(1) / (aspect * tanHalfFovy);
	Result[1][1] = static_cast<T>(1) / (tanHalfFovy);
	Result[2][2] = - (zFar + zNear) / (zFar - zNear);
	Result[2][3] = - static_cast<T>(1);
	Result[3][2] = - (static_cast<T>(2) * zFar * zNear) / (zFar - zNear);
	return Result;
}

template<typename T>
GLM_FUNC_QUALIFIER mat<4, 4, T, defaultp> perspectiveLH_NO(T fovy, T aspect, T zNear, T zFar)
{
	assert(abs(aspect - std::numeric_limits<T>::epsilon()) > static_cast<T>(0));

	T const tanHalfFovy = tan(fovy / static_cast<T>(2));

	mat<4, 4, T, defaultp> Result(static_cast<T>(0));
	Result[0][0] = static_cast<T>(1) / (aspect * tanHalfFovy);
	Result[1][1] = static_cast<T>(1) / (tanHalfFovy);
	Result[2][2] = (zFar + zNear) / (zFar - zNear);
	Result[2][3] = static_cast<T>(1);
	Result[3][2] = - (static_cast<T>(2) * zFar * zNear) / (zFar - zNear);
	return Result;
}

*/

// ------- All glm matrices <-----------


// Mat3x3 -----------------------------------------------------------------------------------

/*
	fn Matrix3x3 Matrix3x3.inverse_new(&self) {
	Matrix3x3 res = *self;
	res.inverse_inplace();
	return res;
	}

	fn void Matrix3x3.inverse_inplace(&s) {
	Matrix3x3 adj @noinit;
	adj.set_at(0, s.at(4) * s.at(8) - s.at(5) * s.at(7));
	adj.set_at(1, s.at(3) * s.at(8) - s.at(5) * s.at(6));
	adj.set_at(2, s.at(3) * s.at(7) - s.at(4) * s.at(6));
	adj.set_at(3, s.at(8) * s.at(1) - s.at(7) * s.at(2));
	adj.set_at(4, s.at(0) * s.at(8) - s.at(2) * s.at(6));
	adj.set_at(5, s.at(7) * s.at(0) - s.at(6) * s.at(1));
	adj.set_at(6, s.at(1) * s.at(5) - s.at(2) * s.at(4));
	adj.set_at(7, s.at(0) * s.at(5) - s.at(2) * s.at(3));
	adj.set_at(8, s.at(0) * s.at(4) - s.at(1) * s.at(3));

	float det = (s.at(0) * adj.at(0)) + (s.at(1) * adj.at(3)) + (s.at(2) * adj.at(4));
	if (math::abs(det) < math::FLOAT_EPSILON) {
	s.identity_inplace();
	return;
	}

	float inv_det = 1 / det;
	Vec3 inv_det_v = { inv_det, inv_det, inv_det };
	for (uint i = 0; i < M3_ROWS; ++i) {
	s.set_row(i, adj.get_row(i) * inv_det_v);
	}
	}

	fn Matrix3x3 Matrix3x3.transpose_new(&self) {
	Matrix3x3 res = *self;
	res.transpose_inplace();
	return res;
	}

	fn void Matrix3x3.transpose_inplace(&self) {
	util::swap_ptrs(self.at_ptr(1), self.at_ptr(3));
	util::swap_ptrs(self.at_ptr(2), self.at_ptr(6));
	util::swap_ptrs(self.at_ptr(5), self.at_ptr(7));
	}
*/

// Mat4x4 -----------------------------------------------------------------------------------

/*
	fn Mat4 Mat4.mul_many_new(&self, Mat4[] inputs) { Mat4 res = M4_IDENTITY; res.mul_many_inplace(inputs); return res; }

	fn void Mat4.mul_many_inplace(&self, Mat4[] inputs) {
	for (uint y = 0; y < M4_ROWS; ++y) {
	Vec4 row = self.get_row(y);
	Vec4 col @noinit;
	Vec4 between_res @noinit;

	foreach (&input_mat : inputs) {
		for (uint x = 0; x < M4_COLS; ++x) {
		col = input_mat.get_col(x);
		between_res[x] = row.dot(col);
		}
		row = between_res;
		}

		self.set_row(y, row);
		}
	}

	fn Mat4 Mat4.transpose_new(&self) {
		Mat4 res = *self;
		res.transpose_inplace();
		return res;
	}

	fn void Mat4.transpose_inplace(&self) {
		util::swap_ptrs(self.at_ptr(1), self.at_ptr(4));
		util::swap_ptrs(self.at_ptr(2), self.at_ptr(8));
		util::swap_ptrs(self.at_ptr(3), self.at_ptr(12));
		util::swap_ptrs(self.at_ptr(6), self.at_ptr(9));
		util::swap_ptrs(self.at_ptr(7), self.at_ptr(13));
		util::swap_ptrs(self.at_ptr(11), self.at_ptr(14));
	}

	fn Mat4 Mat4.inverse_new(&self) {
		Mat4 res = *self;
		res.inverse_inplace();
		return res;
	}

	fn void Mat4.inverse_inplace(&self) {
		if (self.is_affine()) {
			self.inverse_affine_inplace();
		} else {
			self.inverse_general_inplace();
		}
	}

	// NOTE: this should be known from the context
	// computing this explicitly would be expensive, though can be used in Debug mode
	fn bool Mat4.is_orthogonal(&self) {
	Mat4 transpose = self.transpose_new();
	Mat4 res = self.mul_new(&transpose);
	return res.is_identity();
	}

	fn bool Mat4.is_affine(&self) {
	Vec4 affine_row = { 0, 0, 0, 1 };
	Vec4 last_row_v = self.get_row(3);
	return last_row_v == affine_row;
	}

	// NOTE: faster than affine, so if you know that where was no scale on input matrix,
	// it's better to use this instead of affine
	///////////////////////////////////////////////////////////////////////////////
	// compute the inverse of 4x4 Euclidean transformation matrix
	//
	// Euclidean transformation is translation, rotation, and reflection.
	// With Euclidean transform, only the position and orientation of the object
	// will be changed. Euclidean transform does not change the shape of an object
	// (no scaling). Length and angle are reserved.
	//
	// Use inverseAffine() if the matrix has scale and shear transformation.
	//
	// M = [ R | T ]
	//     [ --+-- ]    (R denotes 3x3 rotation/reflection matrix)
	//     [ 0 | 1 ]    (T denotes 1x3 translation matrix)
	//
	// y = M*x  ->  y = R*x + T  ->  x = R^-1*(y - T)  ->  x = R^T*y - R^T*T
	// (R is orthogonal,  R^-1 = R^T)
	//
	//  [ R | T ]-1    [ R^T | -R^T * T ]    (R denotes 3x3 rotation matrix)
	//  [ --+-- ]   =  [ ----+--------- ]    (T denotes 1x3 translation)
	//  [ 0 | 1 ]      [  0  |     1    ]    (R^T denotes R-transpose)

	fn void Mat4.inverse_euclidean_inplace(&self) {
	util::swap_ptrs(self.at_ptr(1), self.at_ptr(4));
	util::swap_ptrs(self.at_ptr(2), self.at_ptr(8));
	util::swap_ptrs(self.at_ptr(6), self.at_ptr(9));
	Matrix3x3 sub_mat = m3_from_m4(self);
	Vec3 translate_col = sub_mat.mul_vec3(self.get_translation_vec());
	translate_col *= -1;
	self.set_translation_vec(translate_col);
	}

	// NOTE: faster than inverse_general, but slower than inverse_euclidean
	// should be used if matrix has scale
	///////////////////////////////////////////////////////////////////////////////
	// compute the inverse of a 4x4 affine transformation matrix
	//
	// Affine transformations are generalizations of Euclidean transformations.
	// Affine transformation includes translation, rotation, reflection, scaling,
	// and shearing. Length and angle are NOT preserved.
	// M = [ R | T ]
	//     [ --+-- ]    (R denotes 3x3 rotation/scale/shear matrix)
	//     [ 0 | 1 ]    (T denotes 1x3 translation matrix)
	//
	// y = M*x  ->  y = R*x + T  ->  x = R^-1*(y - T)  ->  x = R^-1*y - R^-1*T
	//
	//  [ R | T ]-1   [ R^-1 | -R^-1 * T ]
	//  [ --+-- ]   = [ -----+---------- ]
	//  [ 0 | 1 ]     [  0   +     1     ]
	///////////////////////////////////////////////////////////////////////////////
	// NOTE: formula: https://stackoverflow.com/questions/2624422/efficient-4x4-matrix-inverse-affine-transform

	fn void Mat4.inverse_affine_inplace(&self) {
	Matrix3x3 sub_mat = m3_from_m4(self);
	sub_mat.inverse_inplace();

	self.set_row_from_vec3(0, sub_mat.get_row(0));
	self.set_row_from_vec3(1, sub_mat.get_row(1));
	self.set_row_from_vec3(2, sub_mat.get_row(2));

	Vec3 translate_vec = sub_mat.mul_vec3(self.get_translation_vec());
	translate_vec *= -1;
	self.set_translation_vec(translate_vec);
	}

	// NOTE: this is slowest version of invert,
	// only for matrices which have a projection row non empty (!= [0, 0, 0, 1])
	// use inverse_affine of inverse_euclidean if you can
	///////////////////////////////////////////////////////////////////////////////
	// compute the inverse of a general 4x4 matrix using Cramer's Rule
	// If cannot find inverse, return indentity matrix
	// M^-1 = adj(M) / det(M)

	fn void Mat4.inverse_general_inplace(&m) {
	float cofactor0 = cofactor(m.at(5), m.at(6), m.at(7), m.at(9), m.at(10), m.at(11), m.at(13), m.at(14), m.at(15));
	float cofactor1 = cofactor(m.at(4), m.at(6), m.at(7), m.at(8), m.at(10), m.at(11), m.at(12), m.at(14), m.at(15));
	float cofactor2 = cofactor(m.at(4), m.at(5), m.at(7), m.at(8), m.at(9), m.at(11), m.at(12), m.at(13), m.at(15));
	float cofactor3 = cofactor(m.at(4), m.at(5), m.at(6), m.at(8), m.at(9), m.at(10), m.at(12), m.at(13), m.at(14));

	float det = m.at(0) * cofactor0 - m.at(1) * cofactor1 + m.at(2) * cofactor2 - m.at(3) * cofactor3;
	if (math::abs(det) <= math::FLOAT_EPSILON) {
	m.identity_inplace();
	return;
	}

	float cofactor4 = cofactor(m.at(1), m.at(2), m.at(3), m.at(9), m.at(10), m.at(11), m.at(13), m.at(14), m.at(15));
	float cofactor5 = cofactor(m.at(0), m.at(2), m.at(3), m.at(8), m.at(10), m.at(11), m.at(12), m.at(14), m.at(15));
	float cofactor6 = cofactor(m.at(0), m.at(1), m.at(3), m.at(8), m.at(9), m.at(11), m.at(12), m.at(13), m.at(15));
	float cofactor7 = cofactor(m.at(0), m.at(1), m.at(2), m.at(8), m.at(9), m.at(10), m.at(12), m.at(13), m.at(14));

	float cofactor8 = cofactor(m.at(1), m.at(2), m.at(3), m.at(5), m.at(6), m.at(7), m.at(13), m.at(14), m.at(15));
	float cofactor9 = cofactor(m.at(0), m.at(2), m.at(3), m.at(4), m.at(6), m.at(7), m.at(12), m.at(14), m.at(15));
	float cofactor10 = cofactor(m.at(0), m.at(1), m.at(3), m.at(4), m.at(5), m.at(7), m.at(12), m.at(13), m.at(15));
	float cofactor11 = cofactor(m.at(0), m.at(1), m.at(2), m.at(4), m.at(5), m.at(6), m.at(12), m.at(13), m.at(14));

	float cofactor12 = cofactor(m.at(1), m.at(2), m.at(3), m.at(5), m.at(6), m.at(7), m.at(9), m.at(10), m.at(11));
	float cofactor13 = cofactor(m.at(0), m.at(2), m.at(3), m.at(4), m.at(6), m.at(7), m.at(8), m.at(10), m.at(11));
	float cofactor14 = cofactor(m.at(0), m.at(1), m.at(3), m.at(4), m.at(5), m.at(7), m.at(8), m.at(9), m.at(11));
	float cofactor15 = cofactor(m.at(0), m.at(1), m.at(2), m.at(4), m.at(5), m.at(6), m.at(8), m.at(9), m.at(10));

	// build inverse matrix = adj(M) / det(M)
	// adjugate of M is the transpose of the cofactor matrix of M
	float inv_det = 1.0f / det;

	Vec4 row0 = {
	inv_det * cofactor0,
	-inv_det * cofactor4,
	inv_det * cofactor8,
	-inv_det * cofactor12,
	};
	m.set_row(0, row0);

	Vec4 row1 = {
	-inv_det * cofactor1,
	inv_det * cofactor5,
	-inv_det * cofactor9,
	inv_det * cofactor13,
	};
	m.set_row(1, row1);

	Vec4 row2 = {
	inv_det * cofactor2,
	-inv_det * cofactor6,
	inv_det * cofactor10,
	-inv_det * cofactor14,
	};
	m.set_row(2, row2);

	Vec4 row3 = {
	-inv_det * cofactor3,
	inv_det * cofactor7,
	-inv_det * cofactor11,
	inv_det * cofactor15,
	};
	m.set_row(3, row3);
	}

	// NOTE: fast video https://www.youtube.com/watch?v=NEOqegcMw-Q
	fn float Mat4.determinant(&m) {
	return m.at(0) * cofactor(m.at(5), m.at(6), m.at(7), m.at(9), m.at(10), m.at(11), m.at(13), m.at(14), m.at(15)) -
	m.at(1) * cofactor(m.at(4), m.at(6), m.at(7), m.at(8), m.at(10), m.at(11), m.at(12), m.at(14), m.at(15)) +
	m.at(2) * cofactor(m.at(4), m.at(5), m.at(7), m.at(8), m.at(9), m.at(11), m.at(12), m.at(13), m.at(15)) -
	m.at(3) * cofactor(m.at(4), m.at(5), m.at(6), m.at(8), m.at(9), m.at(10), m.at(12), m.at(13), m.at(14));
	}

	// cofactor of 3x3 submatrix
	fn float cofactor(float m0, float m1, float m2, float m3, float m4, float m5, float m6, float m7, float m8) {
	return m0 * (m4 * m8 - m5 * m7) -
	m1 * (m3 * m8 - m5 * m6) +
	m2 * (m3 * m7 - m4 * m6);
	}
*/
