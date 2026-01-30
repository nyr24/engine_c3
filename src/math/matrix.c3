module std::math;

import std::io;

alias Mat4 = matrix::Matrix4x4{float};
alias Mat3 = matrix::Matrix3x3{float};
alias M4_IDENTITY = matrix::IDENTITY4{float};
alias M3_IDENTITY = matrix::IDENTITY3{float};

const M4_LEN = 16;
const M4_ROWS = 4;
const M4_COLS = 4;
const M3_LEN = 9;
const M3_ROWS = 3;
const M3_COLS = 3;

fn void Mat4.print(&m) {
	for (uint i = 0; i < M4_ROWS; ++i) {
		io::printfn("%.2f %.2f %.2f %.2f", m.m[i*4], m.m[i*4 + 1], m.m[i*4 + 2], m.m[i*4 + 3]);
	}
}

fn void Mat3.print(&m) {
	for (uint i = 0; i < M3_ROWS; ++i) {
		io::printfn("%.2f %.2f %.2f", m.m[i*3], m.m[i*3 + 1], m.m[i*3 + 2]);
	}
}

// non throwing wrapper
fn Mat4 Mat4.n_inverse(&m) {
	return m.inverse() ?? M4_IDENTITY;
}

fn void Mat4.n_inverse_inplace(&m) {
	*m = m.inverse() ?? M4_IDENTITY;
}

// Mat3x3 -----------------------------------------------------------------------------------


// struct Matrix3x3 (Printable) {
// 	union data {
// 		Vec3[M3_ROWS] rows;
// 		float[M3_LEN] single;
// 	}
// }

// const Matrix3x3 M3_IDENTITY = {
// 	.data = {
// 		.rows = {
// 			{ 1, 0, 0 },
// 			{ 0, 1, 0 },
// 			{ 0, 0, 1 },
// 		}
// 	}
// };

// fn Matrix3x3 m3_new(float[M3_LEN]* values) {
// 	Matrix3x3 res @noinit;
// 	for (uint i = 0; i < M3_LEN; ++i) {
// 		res.data.single[i] = (*values)[i];
// 	}
// 	return res;
// }

// fn Matrix3x3 m3_from_rows(Vec3[M3_ROWS]* input_rows) {
// 	Matrix3x3 res @noinit;
// 	for (uint y = 0; y < M3_ROWS; ++y) {
// 		res.data.rows[y] = (*input_rows)[y];
// 	}
// 	return res;
// }

// fn Matrix3x3 m3_from_m4(Matrix4x4* mat4) {
// 	Matrix3x3 res @noinit;
// 	for (uint y = 0; y < M3_ROWS; ++y) {
//         res.set_row(y, mat4.get_row_as_vec3(y));
//     }
//     return res;
// }

// fn Matrix3x3 m3_identity() @inline {
// 	return M3_IDENTITY;
// }

// fn void Matrix3x3.identity_inplace(&self) {
// 	*self = M3_IDENTITY;
// }

// fn bool Matrix3x3.is_identity(&self) {
// 	return self.eq(&M3_IDENTITY);
// }

// fn Matrix3x3 Matrix3x3.mul_new(Matrix3x3* self, Matrix3x3* rhs) {
// 	Matrix3x3 res = *self;
// 	res.mul_inplace(rhs);
// 	return res;
// }

// fn void Matrix3x3.mul_inplace(Matrix3x3* self, Matrix3x3* rhs) {
// 	for (uint y = 0; y < M3_ROWS; ++y) {
// 		Vec3 temp_row @noinit;
// 		Vec3 lv = self.get_row(y);
// 		for (uint x = 0; x < M3_COLS; ++x) {
// 			Vec3 rv = rhs.get_col(x);
// 			temp_row[x] = lv.dot(rv);
// 		}
// 		self.set_row(y, temp_row);
// 	}
// }

// fn Vec3 Matrix3x3.mul_vec3(&self, Vec3 rhs) {
//     Vec3 res @noinit;
//     for (uint y = 0; y < M3_ROWS; ++y) {
//         Vec3 row = self.get_row(y);
//         res[y] = row.dot(rhs);
//     }
//     return res;
// }

// fn Matrix3x3 Matrix3x3.inverse_new(&self) {
// 	Matrix3x3 res = *self;
// 	res.inverse_inplace();
// 	return res;
// }

// fn void Matrix3x3.inverse_inplace(&s) {
// 	Matrix3x3 adj @noinit;
// 	adj.set_at(0, s.at(4) * s.at(8) - s.at(5) * s.at(7));
// 	adj.set_at(1, s.at(3) * s.at(8) - s.at(5) * s.at(6));
// 	adj.set_at(2, s.at(3) * s.at(7) - s.at(4) * s.at(6));
// 	adj.set_at(3, s.at(8) * s.at(1) - s.at(7) * s.at(2));
// 	adj.set_at(4, s.at(0) * s.at(8) - s.at(2) * s.at(6));
// 	adj.set_at(5, s.at(7) * s.at(0) - s.at(6) * s.at(1));
// 	adj.set_at(6, s.at(1) * s.at(5) - s.at(2) * s.at(4));
// 	adj.set_at(7, s.at(0) * s.at(5) - s.at(2) * s.at(3));
// 	adj.set_at(8, s.at(0) * s.at(4) - s.at(1) * s.at(3));

// 	float det = (s.at(0) * adj.at(0)) + (s.at(1) * adj.at(3)) + (s.at(2) * adj.at(4));
// 	if (math::abs(det) < math::FLOAT_EPSILON) {
// 		s.identity_inplace();
// 		return;
// 	}

// 	float inv_det = 1 / det;
// 	Vec3 inv_det_v = { inv_det, inv_det, inv_det };
// 	for (uint i = 0; i < M3_ROWS; ++i) {
// 		s.set_row(i, adj.get_row(i) * inv_det_v);
// 	}
// }

// fn Matrix3x3 Matrix3x3.transpose_new(&self) {
// 	Matrix3x3 res = *self;
// 	res.transpose_inplace();
// 	return res;
// }

// fn void Matrix3x3.transpose_inplace(&self) {
// 	util::swap_ptrs(self.at_ptr(1), self.at_ptr(3));
// 	util::swap_ptrs(self.at_ptr(2), self.at_ptr(6));
// 	util::swap_ptrs(self.at_ptr(5), self.at_ptr(7));
// }

// fn float Matrix3x3.at(&self, uint ind) @inline {
// 	assert(ind < M3_LEN);
// 	return self.data.single[ind];
// }

// fn float* Matrix3x3.at_ptr(&self, uint ind) @inline {
// 	assert(ind < M3_LEN);
// 	return &self.data.single[ind];
// }

// fn float Matrix3x3.at_rc(&self, uint row, uint col) @inline {
// 	assert(row < M3_ROWS);
// 	assert(col < M3_COLS);
// 	return self.data.rows[row][col];
// }

// fn float* Matrix3x3.at_rc_ptr(&self, uint row, uint col) @inline {
// 	assert(row < M3_ROWS);
// 	assert(col < M3_COLS);
// 	return &self.data.rows[row][col];
// }

// fn void Matrix3x3.set_at(&self, uint ind, float val) @inline {
// 	assert(ind < M3_LEN);
// 	self.data.single[ind] = val;
// }

// fn void Matrix3x3.set_at_rc(&self, uint row, uint col, float val) @inline {
// 	assert(row < M3_ROWS);
// 	assert(col < M3_COLS);
// 	self.data.rows[row][col] = val;
// }

// fn Vec3 Matrix3x3.get_row(&self, uint ind) @inline {
// 	assert(ind < M3_ROWS);
// 	return self.data.rows[ind];
// }

// fn Vec3* Matrix3x3.get_row_ptr(&self, uint ind) @inline {
// 	assert(ind < M3_ROWS);
// 	return &self.data.rows[ind];
// }

// fn void Matrix3x3.set_row(&self, uint ind, Vec3 new_row) @inline {
// 	assert(ind < M3_ROWS);
// 	self.data.rows[ind] = new_row;
// }

// fn Vec3 Matrix3x3.get_col(&self, uint ind) {
// 	assert(ind < M3_COLS);

// 	Vec3 col @noinit;
// 	for (int i = 0; i < M3_ROWS; ++i) {
// 		col[i] = self.data.rows[i][ind];
// 	}
// 	return col;
// }

// fn void Matrix3x3.set_col(&self, uint ind, Vec3 new_col) {
// 	assert(ind < M3_COLS);

// 	for (int i = 0; i < M3_ROWS; ++i) {
// 		self.data.rows[i][ind] = new_col[i];
// 	}
// }

// fn Vec3 Matrix3x3.get_scaling_vec(&self) {
// 	Vec3 res @noinit;
// 	res[0] = self.data.single[0];
// 	res[1] = self.data.single[4];
// 	res[2] = self.data.single[8];
// 	return res;
// }

// fn void Matrix3x3.set_scaling_vec(&self, Vec3 scaling_vec) @private {
// 	self.data.single[0] = scaling_vec[0];
// 	self.data.single[4] = scaling_vec[1];
// 	self.data.single[8] = scaling_vec[2];
// }

// fn usz? Matrix3x3.to_format(&self, Formatter* formatter) @dynamic {
// 	usz n;
// 	for (uint i = 0; i < M3_ROWS; ++i) {
// 		n += formatter.printf("%s\n", self.data.rows[i])!;
// 	}
// 	return n;
// }

// fn bool Matrix3x3.eq(&self, Matrix3x3* rhs) {
// 	for (uint i = 0; i < M3_LEN; ++i) {
// 		if (self.at(i) != rhs.at(i)) {
// 			return false;
// 		}
// 	}
// 	return true;
// }

// // Mat4x4 -----------------------------------------------------------------------------------

// struct Matrix4x4 (Printable) {
// 	union data {
// 		Vec4[M4_ROWS] rows;
// 		float[M4_LEN] single;
// 	}
// }

// const Matrix4x4 M4_IDENTITY = {
// 	.data = {
// 		.rows = {
// 			{ 1, 0, 0, 0 },
// 			{ 0, 1, 0, 0 },
// 			{ 0, 0, 1, 0 },
// 			{ 0, 0, 0, 1 },
// 		}
// 	}
// };

// enum Axis : uint {
// 	X, Y, Z
// }

// fn Matrix4x4 m4_new(float[M4_LEN]* values) {
// 	Matrix4x4 res @noinit;
// 	for (uint i = 0; i < M4_LEN; ++i) {
// 		res.data.single[i] = (*values)[i];
// 	}
// 	return res;
// }

// fn Matrix4x4 m4_from_rows(Vec4[4]* input_rows) {
// 	Matrix4x4 res @noinit;
// 	for (uint y = 0; y < M4_ROWS; ++y) {
// 		res.data.rows[y] = (*input_rows)[y];
// 	}
// 	return res;
// }

// fn Matrix4x4 m4_from_m3(Matrix3x3* mat3) {
// 	Matrix4x4 res @noinit;
//     for (uint y = 0; y < M3_ROWS; ++y) {
//         for (uint x = 0; x < M3_COLS; ++x) {
//             res.set_at_rc(y, x, mat3.at_rc(y, x));
//         }
//     }
//     res.set_col(3, { 0, 0, 0, 1 });
//     res.set_row(3, { 0, 0, 0, 1 });
// 	return res;
// }

// fn Matrix4x4 m4_identity() @inline {
// 	return M4_IDENTITY;
// }

// fn void Matrix4x4.identity_inplace(&self) {
// 	*self = M4_IDENTITY;
// }

// fn bool Matrix4x4.is_identity(&self) {
// 	return self.eq(&M4_IDENTITY);
// }

// fn Matrix4x4 m4_translation(Vec3 translation_vec) {
//     Matrix4x4 res = M4_IDENTITY;
//     res.set_translation_vec(translation_vec);
//     return res;
// }

// fn void Matrix4x4.translate_inplace(&self, Vec3 translation_vec) {
//     Matrix4x4 rhs = m4_translation(translation_vec);
//     self.mul_inplace(&rhs);
// }

// fn Matrix4x4 m4_scaling(Vec3 scaling_vec) {
//     Matrix4x4 res = M4_IDENTITY;
//     res.set_scaling_vec(scaling_vec);
//     return res;
// }

// fn void Matrix4x4.scale_inplace(&self, Vec3 scaling_vec) {
//     Matrix4x4 rhs = m4_scaling(scaling_vec);
//     self.mul_inplace(&rhs);
// }

// fn Matrix4x4 m4_rotation(float rotate_deg, Axis axis) {
// 	Matrix4x4 res = M4_IDENTITY;
//     res.rotate_inplace(rotate_deg, axis);
//     return res;
// }

// fn void Matrix4x4.rotate_inplace(&self, float rotate_deg, Axis axis) {
//     float sin = (float)math::sin(math::deg_to_rad(rotate_deg));
//     float cos = (float)math::cos(math::deg_to_rad(rotate_deg));

//     switch (axis) {
//         case Axis.X: {
//             self.set_at(5, cos);
//             self.set_at(6, -sin);
//             self.set_at(9, sin);
//             self.set_at(10, cos);
// 		}
//         case Axis.Y: {
//             self.set_at(0, cos);
//             self.set_at(2, sin);
//             self.set_at(8, -sin);
//             self.set_at(10, cos);
// 		}
//         case Axis.Z: {
//             self.set_at(0, cos);
//             self.set_at(1, -sin);
//             self.set_at(4, sin);
//             self.set_at(5, cos);
// 		}
//     }
// }

// fn Matrix4x4 m4_rotation_arbitrary_axis(float angle_deg, Vec3 axis) {
//     Matrix4x4 res = M4_IDENTITY;
// 	res.rotate_arbitrary_axis_inplace(angle_deg, axis);
//     return res;
// }

// fn void Matrix4x4.rotate_arbitrary_axis_inplace(&self, float angle_deg, Vec3 axis) {
//     float angle_rad = (float)math::deg_to_rad(angle_deg);
//     float cos = (float)math::cos(angle_rad);
//     float sin = (float)math::sin(angle_rad);
//     float t = 1.0 - cos;
//     float x = axis.x;
//     float y = axis.y;
//     float z = axis.z;

//     Vec4 row_0 = {
//         t * x * x + cos,
//         t * x * y - sin * z,
//         t * x * z + sin * y,
//         0,
//     };
//     self.set_row(0, row_0);

//     Vec4 row_1 = {
//         t * x * y + sin * z,
//         t * y * y + cos,
//         t * y * z - sin * x,
//         0,
//     };
//     self.set_row(1, row_1);

//     Vec4 row_2 = {
//         t * x * z - sin * y,
//         t * y * z + sin * x,
//         t * z * z + cos,
//         0,
//     };
//     self.set_row(2, row_2);
// }

// fn Matrix4x4 m4_rotation_many(AxisAngle[] axis_angles) {
//     Matrix4x4 res = M4_IDENTITY;
// 	res.rotate_many_inplace(axis_angles);
//     return res;
// }

// fn void Matrix4x4.rotate_many_inplace(&self, AxisAngle[] axis_angles) {
// 	const MAX_ALLOWED_INPUT = 6;
// 	assert(axis_angles.len > MAX_ALLOWED_INPUT);
// 	FixedArray{Matrix4x4, MAX_ALLOWED_INPUT} matrices;

// 	foreach (axis_angle : axis_angles) {
// 		Matrix4x4* mat = matrices.pull();
// 		mat.rotate_arbitrary_axis_inplace(axis_angle.angle, axis_angle.axis);
// 	}
	
//     self.mul_many_inplace(&matrices.entries);
// }

// fn Matrix4x4 Matrix4x4.mul_new(Matrix4x4* self, Matrix4x4* rhs) {
// 	Matrix4x4 res = *self;
// 	res.mul_inplace(rhs);
// 	return res;
// }

// fn void Matrix4x4.mul_inplace(Matrix4x4* self, Matrix4x4* rhs) {
// 	for (uint y = 0; y < M4_ROWS; ++y) {
// 		Vec4 temp_row @noinit;
// 		Vec4 lv = self.get_row(y);
// 		for (uint x = 0; x < M4_COLS; ++x) {
// 			Vec4 rv = rhs.get_col(x);
// 			temp_row[x] = lv.dot(rv);
// 		}
// 		self.set_row(y, temp_row);
// 	}
// }

// fn Matrix4x4 Matrix4x4.mul_many_new(&self, Matrix4x4[] inputs) {
//     Matrix4x4 res = M4_IDENTITY;
// 	res.mul_many_inplace(inputs);
//     return res;
// }

// fn void Matrix4x4.mul_many_inplace(&self, Matrix4x4[] inputs) {
//     for (uint y = 0; y < M4_ROWS; ++y) {
//         Vec4 row = self.get_row(y);
//         Vec4 col @noinit;
//         Vec4 between_res @noinit;

//         foreach (&input_mat : inputs) {
// 		    for (uint x = 0; x < M4_COLS; ++x) {
//                 col = input_mat.get_col(x);
//                 between_res[x] = row.dot(col);
//             }
//             row = between_res;
//         }

//         self.set_row(y, row);
//     }
// }

// fn Vec4 Matrix4x4.mul_vec4(&self, Vec4 rhs) {
//     Vec4 res @noinit;

//     for (uint y = 0; y < M4_ROWS; ++y) {
//         Vec4 row = self.get_row(y);
//         res[y] = row.dot(rhs);
//     }

//     return res;
// }

// fn Matrix4x4 Matrix4x4.transpose_new(&self) {
//     Matrix4x4 res = *self;
//     res.transpose_inplace();
//     return res;
// }

// fn void Matrix4x4.transpose_inplace(&self) {
//     util::swap_ptrs(self.at_ptr(1), self.at_ptr(4));
//     util::swap_ptrs(self.at_ptr(2), self.at_ptr(8));
//     util::swap_ptrs(self.at_ptr(3), self.at_ptr(12));
//     util::swap_ptrs(self.at_ptr(6), self.at_ptr(9));
//     util::swap_ptrs(self.at_ptr(7), self.at_ptr(13));
//     util::swap_ptrs(self.at_ptr(11), self.at_ptr(14));
// }

// fn Matrix4x4 Matrix4x4.inverse_new(&self) {
//     Matrix4x4 res = *self;
//     res.inverse_inplace();
//     return res;
// }

// fn void Matrix4x4.inverse_inplace(&self) {
//     if (self.is_affine()) {
//         self.inverse_affine_inplace();
//     } else {
//         self.inverse_general_inplace();
//     }
// }

// // NOTE: this should be known from the context
// // computing this explicitly would be expensive, though can be used in Debug mode
// fn bool Matrix4x4.is_orthogonal(&self) {
//     Matrix4x4 transpose = self.transpose_new();
//     Matrix4x4 res = self.mul_new(&transpose);
//     return res.is_identity();
// }

// fn bool Matrix4x4.is_affine(&self) {
//     Vec4 affine_row = { 0, 0, 0, 1 };
//     Vec4 last_row_v = self.get_row(3);
//     return last_row_v == affine_row;
// }

// // NOTE: faster than affine, so if you know that where was no scale on input matrix,
// // it's better to use this instead of affine
// ///////////////////////////////////////////////////////////////////////////////
// // compute the inverse of 4x4 Euclidean transformation matrix
// //
// // Euclidean transformation is translation, rotation, and reflection.
// // With Euclidean transform, only the position and orientation of the object
// // will be changed. Euclidean transform does not change the shape of an object
// // (no scaling). Length and angle are reserved.
// //
// // Use inverseAffine() if the matrix has scale and shear transformation.
// //
// // M = [ R | T ]
// //     [ --+-- ]    (R denotes 3x3 rotation/reflection matrix)
// //     [ 0 | 1 ]    (T denotes 1x3 translation matrix)
// //
// // y = M*x  ->  y = R*x + T  ->  x = R^-1*(y - T)  ->  x = R^T*y - R^T*T
// // (R is orthogonal,  R^-1 = R^T)
// //
// //  [ R | T ]-1    [ R^T | -R^T * T ]    (R denotes 3x3 rotation matrix)
// //  [ --+-- ]   =  [ ----+--------- ]    (T denotes 1x3 translation)
// //  [ 0 | 1 ]      [  0  |     1    ]    (R^T denotes R-transpose)

// fn void Matrix4x4.inverse_euclidean_inplace(&self) {
//     util::swap_ptrs(self.at_ptr(1), self.at_ptr(4));
//     util::swap_ptrs(self.at_ptr(2), self.at_ptr(8));
//     util::swap_ptrs(self.at_ptr(6), self.at_ptr(9));
//     Matrix3x3 sub_mat = m3_from_m4(self);
//     Vec3 translate_col = sub_mat.mul_vec3(self.get_translation_vec());
//     translate_col *= -1;
//     self.set_translation_vec(translate_col);
// }

// // NOTE: faster than inverse_general, but slower than inverse_euclidean
// // should be used if matrix has scale
// ///////////////////////////////////////////////////////////////////////////////
// // compute the inverse of a 4x4 affine transformation matrix
// //
// // Affine transformations are generalizations of Euclidean transformations.
// // Affine transformation includes translation, rotation, reflection, scaling,
// // and shearing. Length and angle are NOT preserved.
// // M = [ R | T ]
// //     [ --+-- ]    (R denotes 3x3 rotation/scale/shear matrix)
// //     [ 0 | 1 ]    (T denotes 1x3 translation matrix)
// //
// // y = M*x  ->  y = R*x + T  ->  x = R^-1*(y - T)  ->  x = R^-1*y - R^-1*T
// //
// //  [ R | T ]-1   [ R^-1 | -R^-1 * T ]
// //  [ --+-- ]   = [ -----+---------- ]
// //  [ 0 | 1 ]     [  0   +     1     ]
// ///////////////////////////////////////////////////////////////////////////////
// // NOTE: formula: https://stackoverflow.com/questions/2624422/efficient-4x4-matrix-inverse-affine-transform

// fn void Matrix4x4.inverse_affine_inplace(&self) {
//     Matrix3x3 sub_mat = m3_from_m4(self);
//     sub_mat.inverse_inplace();

//     self.set_row_from_vec3(0, sub_mat.get_row(0));
//     self.set_row_from_vec3(1, sub_mat.get_row(1));
//     self.set_row_from_vec3(2, sub_mat.get_row(2));

//     Vec3 translate_vec = sub_mat.mul_vec3(self.get_translation_vec());
//     translate_vec *= -1;
//     self.set_translation_vec(translate_vec);
// }

// // NOTE: this is slowest version of invert,
// // only for matrices which have a projection row non empty (!= [0, 0, 0, 1])
// // use inverse_affine of inverse_euclidean if you can
// ///////////////////////////////////////////////////////////////////////////////
// // compute the inverse of a general 4x4 matrix using Cramer's Rule
// // If cannot find inverse, return indentity matrix
// // M^-1 = adj(M) / det(M)

// fn void Matrix4x4.inverse_general_inplace(&m) {
//     float cofactor0 = cofactor(m.at(5), m.at(6), m.at(7), m.at(9), m.at(10), m.at(11), m.at(13), m.at(14), m.at(15));
//     float cofactor1 = cofactor(m.at(4), m.at(6), m.at(7), m.at(8), m.at(10), m.at(11), m.at(12), m.at(14), m.at(15));
//     float cofactor2 = cofactor(m.at(4), m.at(5), m.at(7), m.at(8), m.at(9), m.at(11), m.at(12), m.at(13), m.at(15));
//     float cofactor3 = cofactor(m.at(4), m.at(5), m.at(6), m.at(8), m.at(9), m.at(10), m.at(12), m.at(13), m.at(14));

//     float det = m.at(0) * cofactor0 - m.at(1) * cofactor1 + m.at(2) * cofactor2 - m.at(3) * cofactor3;
//     if (math::abs(det) <= math::FLOAT_EPSILON) {
//         m.identity_inplace();
//         return;
//     }

//     float cofactor4 = cofactor(m.at(1), m.at(2), m.at(3), m.at(9), m.at(10), m.at(11), m.at(13), m.at(14), m.at(15));
//     float cofactor5 = cofactor(m.at(0), m.at(2), m.at(3), m.at(8), m.at(10), m.at(11), m.at(12), m.at(14), m.at(15));
//     float cofactor6 = cofactor(m.at(0), m.at(1), m.at(3), m.at(8), m.at(9), m.at(11), m.at(12), m.at(13), m.at(15));
//     float cofactor7 = cofactor(m.at(0), m.at(1), m.at(2), m.at(8), m.at(9), m.at(10), m.at(12), m.at(13), m.at(14));

//     float cofactor8 = cofactor(m.at(1), m.at(2), m.at(3), m.at(5), m.at(6), m.at(7), m.at(13), m.at(14), m.at(15));
//     float cofactor9 = cofactor(m.at(0), m.at(2), m.at(3), m.at(4), m.at(6), m.at(7), m.at(12), m.at(14), m.at(15));
//     float cofactor10 = cofactor(m.at(0), m.at(1), m.at(3), m.at(4), m.at(5), m.at(7), m.at(12), m.at(13), m.at(15));
//     float cofactor11 = cofactor(m.at(0), m.at(1), m.at(2), m.at(4), m.at(5), m.at(6), m.at(12), m.at(13), m.at(14));

//     float cofactor12 = cofactor(m.at(1), m.at(2), m.at(3), m.at(5), m.at(6), m.at(7), m.at(9), m.at(10), m.at(11));
//     float cofactor13 = cofactor(m.at(0), m.at(2), m.at(3), m.at(4), m.at(6), m.at(7), m.at(8), m.at(10), m.at(11));
//     float cofactor14 = cofactor(m.at(0), m.at(1), m.at(3), m.at(4), m.at(5), m.at(7), m.at(8), m.at(9), m.at(11));
//     float cofactor15 = cofactor(m.at(0), m.at(1), m.at(2), m.at(4), m.at(5), m.at(6), m.at(8), m.at(9), m.at(10));

//     // build inverse matrix = adj(M) / det(M)
//     // adjugate of M is the transpose of the cofactor matrix of M
//     float inv_det = 1.0f / det;

// 	Vec4 row0 = {
// 	    inv_det * cofactor0,
// 	    -inv_det * cofactor4,
// 	    inv_det * cofactor8,
// 	    -inv_det * cofactor12,
// 	};
// 	m.set_row(0, row0);

// 	Vec4 row1 = {
// 	    -inv_det * cofactor1,
// 	    inv_det * cofactor5,
// 	    -inv_det * cofactor9,
// 	    inv_det * cofactor13,
// 	};
// 	m.set_row(1, row1);

// 	Vec4 row2 = {
// 		inv_det * cofactor2,
// 		-inv_det * cofactor6,
// 		inv_det * cofactor10,
// 		-inv_det * cofactor14,
// 	};
// 	m.set_row(2, row2);

// 	Vec4 row3 = {
// 		-inv_det * cofactor3,
// 		inv_det * cofactor7,
// 	    -inv_det * cofactor11,
// 	    inv_det * cofactor15,
// 	};
// 	m.set_row(3, row3);
// }

// // NOTE: fast video https://www.youtube.com/watch?v=NEOqegcMw-Q
// fn float Matrix4x4.determinant(&m) {
//     return m.at(0) * cofactor(m.at(5), m.at(6), m.at(7), m.at(9), m.at(10), m.at(11), m.at(13), m.at(14), m.at(15)) -
//         m.at(1) * cofactor(m.at(4), m.at(6), m.at(7), m.at(8), m.at(10), m.at(11), m.at(12), m.at(14), m.at(15)) +
//         m.at(2) * cofactor(m.at(4), m.at(5), m.at(7), m.at(8), m.at(9), m.at(11), m.at(12), m.at(13), m.at(15)) -
//         m.at(3) * cofactor(m.at(4), m.at(5), m.at(6), m.at(8), m.at(9), m.at(10), m.at(12), m.at(13), m.at(14));
// }

// // cofactor of 3x3 submatrix
// fn float cofactor(float m0, float m1, float m2, float m3, float m4, float m5, float m6, float m7, float m8) {
//     return m0 * (m4 * m8 - m5 * m7) -
//         m1 * (m3 * m8 - m5 * m6) +
//         m2 * (m3 * m7 - m4 * m6);
// }

// fn Matrix4x4 m4_look_at(Vec3 pos, Vec3 target, Vec3 world_up) {
//     Vec3 dir = target.distance(pos);
//     Vec3 right = world_up.cross(dir);
//     Vec3 up = dir.cross(right);
// 	Vec3 pos_neg = pos * -1;

//     Matrix4x4 res = M4_IDENTITY;
//     res.set_row_from_vec3(0, right);
//     res.set_row_from_vec3(1, up);
//     res.set_row_from_vec3(2, dir);

//     res.translate_inplace(pos_neg);

//     return res;
// }

// // NOTE: article reference https://www.kdab.com/projection-matrices-with-vulkan-part-2/
// fn Matrix4x4 m4_projection(float t, float b, float l, float r, float n, float f) {
//     Matrix4x4 res;
//     res.set_at(0, (2.0f * n) / (r - l));
//     res.set_at(2, -((r + l) / (r - l)));
//     res.set_at(5, (2.0f * n) / (b - t));
//     res.set_at(6, -((b + t) / (b - t)));
//     res.set_at(10, f / (f - n));
//     res.set_at(11, -((n * f) / (f - n)));
//     res.set_at(14, 1.0f);
// 	res.set_at(15, 1.0f);
//     return res;
// }

// fn Matrix4x4 m4_projection_fov(float fov, float aspect, float n, float f) {
//     Matrix4x4 res;
//     float fov_half = (float)math::deg_to_rad(fov / 2);
//     float tan = (float)math::tan(fov_half);
//     float b = tan * n;
//     float r = b * aspect;

//     res.set_at(0, n / r);
//     res.set_at(5, n / b);
//     res.set_at(10, f / (f - n));
//     res.set_at(11, -((n * f) / (f - n)));
//     res.set_at(14, 1.0f);
// 	res.set_at(15, 1.0f);

//     return res;
// }

// fn Matrix4x4 m4_ortho(float t, float b, float l, float r, float n, float f) {
//     Matrix4x4 res;
//     res.set_at(0, 2.0f / (r - l));
//     res.set_at(3, -((r + l) / (r - l)));
//     res.set_at(5, 2.0f / (b - t));
//     res.set_at(7, -((b + t) / (b - t)));
//     res.set_at(10, -2 / (f - n));
//     res.set_at(11, -((f + n) / (f - n)));
// 	res.set_at(15, 1.0);
//     return res;
// }

// fn float Matrix4x4.at(&self, uint ind) @inline {
// 	assert(ind < M4_LEN);
// 	return self.data.single[ind];
// }

// fn float* Matrix4x4.at_ptr(&self, uint ind) @inline {
// 	assert(ind < M4_LEN);
// 	return &self.data.single[ind];
// }

// fn float Matrix4x4.at_rc(&self, uint row, uint col) @inline {
// 	assert(row < M4_ROWS);
// 	assert(col < M4_COLS);
// 	return self.data.rows[row][col];
// }

// fn float* Matrix4x4.at_rc_ptr(&self, uint row, uint col) @inline {
// 	assert(row < M4_ROWS);
// 	assert(col < M4_COLS);
// 	return &self.data.rows[row][col];
// }

// fn void Matrix4x4.set_at(&self, uint ind, float val) @inline {
// 	assert(ind < M4_LEN);
// 	self.data.single[ind] = val;
// }

// fn void Matrix4x4.set_at_rc(&self, uint row, uint col, float val) @inline {
// 	assert(row < M4_ROWS);
// 	assert(col < M4_COLS);
// 	self.data.rows[row][col] = val;
// }

// fn Vec4 Matrix4x4.get_row(&self, uint ind) @inline {
// 	assert(ind < M4_ROWS);
// 	return self.data.rows[ind];
// }

// fn Vec3 Matrix4x4.get_row_as_vec3(&self, uint ind) @inline {
// 	assert(ind < M4_ROWS);
// 	return self.data.rows[ind].xyz;
// }

// fn Vec4* Matrix4x4.get_row_ptr(&self, uint ind) @inline {
// 	assert(ind < M4_ROWS);
// 	return &self.data.rows[ind];
// }

// fn void Matrix4x4.set_row(&self, uint ind, Vec4 new_row) @inline @private {
// 	assert(ind < M4_ROWS);
// 	self.data.rows[ind] = new_row;
// }

// fn void Matrix4x4.set_row_from_vec3(&self, uint ind, Vec3 new_row) @inline @private {
// 	assert(ind < M4_ROWS);
// 	for (uint i = 0; i < Vec3.len; ++i) {
// 		self.data.rows[ind][i] = new_row[i];
// 	}
// }

// fn Vec4 Matrix4x4.get_col(&self, uint ind) {
// 	assert(ind < M4_COLS);

// 	Vec4 col @noinit;
// 	for (uint i = 0; i < M4_ROWS; ++i) {
// 		col[i] = self.data.rows[i][ind];
// 	}
// 	return col;
// }

// fn void Matrix4x4.set_col(&self, uint ind, Vec4 new_col) @private {
// 	assert(ind < M4_COLS);

// 	for (uint i = 0; i < M4_ROWS; ++i) {
// 		self.data.rows[i][ind] = new_col[i];
// 	}
// }

// fn void Matrix4x4.set_col_from_vec3(&self, uint ind, Vec3 new_col) @inline {
// 	assert(ind < M4_COLS);
// 	for (uint i = 0; i < 3; ++i) {
// 		self.data.rows[i][ind] = new_col[i];
// 	}
// }

// fn Vec3 Matrix4x4.get_translation_vec(&self) {
// 	Vec3 res @noinit;
// 	res[0] = self.data.single[3];
// 	res[1] = self.data.single[7];
// 	res[2] = self.data.single[11];
// 	return res;
// }

// fn Vec3 Matrix4x4.get_scaling_vec(&self) {
// 	Vec3 res @noinit;
// 	res[0] = self.data.single[0];
// 	res[1] = self.data.single[4];
// 	res[2] = self.data.single[8];
// 	return res;
// }

// fn void Matrix4x4.set_translation_vec(&self, Vec3 translation_vec) @private {
// 	self.data.single[3] = translation_vec[0];
// 	self.data.single[7] = translation_vec[1];
// 	self.data.single[11] = translation_vec[2];
// }

// fn void Matrix4x4.set_scaling_vec(&self, Vec3 scaling_vec) @private {
// 	self.data.single[0] = scaling_vec[0];
// 	self.data.single[5] = scaling_vec[1];
// 	self.data.single[10] = scaling_vec[2];
// }

// fn usz? Matrix4x4.to_format(&self, Formatter* formatter) @dynamic {
// 	usz n;
// 	for (uint i = 0; i < M4_ROWS; ++i) {
// 		n += formatter.printf("%s\n", self.data.rows[i])!;
// 	}
// 	return n;
// }

// fn bool Matrix4x4.eq(&self, Matrix4x4* rhs) {
// 	for (uint i = 0; i < M4_LEN; ++i) {
// 		if (self.at(i) != rhs.at(i)) {
// 			return false;
// 		}
// 	}
// 	return true;
// }
