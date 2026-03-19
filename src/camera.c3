module engine;

import std::math;
import glfw;

const float DEFAULT_CAMERA_SPEED = 250.0f;
const float CAMERA_ZOOM_SPEED = 2.5f;
const float CAMERA_ZOOM_MIN = 0.1f;
const float CAMERA_ZOOM_MAX = 300.0f;

struct Camera
{
	Vec3 pos;
	Vec3 target;
	Vec3 right;
	Vec3 up;
	float yaw;
	float pitch;
	float speed;
// TODO: make in radians
	float zoom;
	MouseSensivity mouse_sensivity;
	bool dirty;
}

constdef MouseSensivity : inline float
{
	SLOW       = 0.0005f,
	MEDIUM     = 0.0008f,
	FAST       = 0.001f,
	SUPER_FAST = 0.0025f,
}

fn void Camera.init(
	&cam,
	Vec3 pos,
	Vec3 target,
	float speed = DEFAULT_CAMERA_SPEED,
	float zoom = 45.0f
)
{
	cam.pos = pos;
	cam.target = target;
	cam.right = V3_RIGHT;
	cam.up = V3_TOP;
	cam.yaw = math::deg_to_rad(-90.0f);
	cam.pitch = 0;
	cam.speed = speed;
	cam.zoom = zoom;
	cam.dirty = true;
	cam.mouse_sensivity = MouseSensivity.FAST;
}

fn Mat4 Camera.look_at(&cam)
{
	return matrix::look_at(cam.pos, cam.pos + cam.target, cam.up);
}

fn void Camera.handle_mouse_move(&cam, float delta_x, float delta_y)
{
	cam.yaw += delta_x * cam.mouse_sensivity;
	cam.pitch = math::clamp(
		cam.pitch + delta_y * cam.mouse_sensivity,
		math::deg_to_rad(-89.0f),
		math::deg_to_rad(89.0f)
	);
	cam.recalc_state(delta_x, delta_y);
	cam.dirty = true;
}

fn void Camera.handle_key_down(&cam, uint key, double frame_delta_time_sec)
{
	float velocity = cam.speed * (float)frame_delta_time_sec;

	switch (key)
	{
		case glfw::KEY_W:
			cam.pos += cam.target * velocity;
		case glfw::KEY_S:
			cam.pos -= cam.target * velocity;
		case glfw::KEY_D:
			cam.pos += cam.right * velocity;
		case glfw::KEY_A:
			cam.pos -= cam.right * velocity;
		default:
			return;
	}
	cam.dirty = true;
}

// THINK: wheel update don't require look_at update
// so maybe change 'dirty' to bitstruct, so that we know
// which matrix updates are triggerred by camera updates (view, proj, both)
fn void Camera.handle_mouse_wheel(&cam, bool delta)
{
	if (delta)
	{
		cam.zoom += CAMERA_ZOOM_SPEED;
	}
	else
	{
		cam.zoom -= CAMERA_ZOOM_SPEED;
	}
	cam.zoom = math::clamp(cam.zoom, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX);
	cam.dirty = true;
}

fn void Camera.recalc_state(&cam, float delta_x, float delta_y)
{
	cam.target.x = math::cos(cam.yaw) * math::cos(cam.pitch);
	cam.target.y = math::sin(cam.pitch);
	cam.target.z = math::sin(cam.yaw) * math::cos(cam.pitch);
	cam.target = cam.target.normalize();
	cam.right = cam.target.cross(V3_TOP).normalize();
	cam.up = cam.right.cross(cam.target).normalize();
}
