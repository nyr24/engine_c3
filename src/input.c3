module engine;

import std::time;
import glfw;

const MS = 1_000_000;
const NS = 1_000_000_000;

const NanoDuration DEFAULT_KEY_REPEAT_RATE_US = (NanoDuration)(10 * MS);
const NanoDuration DEFAULT_KEY_REPEAT_DELAY_US = (NanoDuration)(100 * MS);

struct InputSystem
{
    MouseState      mouse_curr;
    MouseState      mouse_prev;
    KeyboardState   kb_curr;
    KeyboardState   kb_prev;
    MouseDelta      mouse_delta;
    KeyRepeatGlobalState key_repeat_state;
    KeyRepeatTimer[glfw::KEY_LAST] key_repeat_timers;
	App* 	        app;
// NOTE: TEST
    bool            accept_move_events;
}

// down = true, up = false
alias KeyboardState = bool[glfw::KEY_LAST];
alias MouseDelta = MousePos;

// matches glfw
enum MouseButton : inline uint
{
    LEFT,
    RIGHT,
    MIDDLE,
}

struct MousePos
{
    float x;
    float y;
}

struct MouseState
{
    MousePos pos;
    // down = true, up = false
    bool[MouseButton.len] buttons;
}

struct KeyRepeatGlobalState
{
    NanoDuration rate;
    NanoDuration delay;
}

struct KeyRepeatTimer
{
    TimepointClock clock;
    bool           pass_delay;
}

fn void InputSystem.init(&input_sys, App* app)
{
	mem::clear(input_sys, InputSystem.sizeof);
	input_sys.key_repeat_state.rate = DEFAULT_KEY_REPEAT_RATE_US;
	input_sys.key_repeat_state.delay = DEFAULT_KEY_REPEAT_DELAY_US;
	input_sys.app = app;
}

fn void InputSystem.update(&input_sys)
{
    mem::copy(&input_sys.kb_prev, &input_sys.kb_curr, KeyboardState.sizeof);
    mem::copy(&input_sys.mouse_prev, &input_sys.mouse_curr, MouseState.sizeof);

    for (uint i = 0; i < glfw::KEY_LAST; ++i) {
        if (input_sys.kb_prev[i]) {
            KeyRepeatTimer* timer = &input_sys.key_repeat_timers[i];

            if (!timer.clock.is_running()) {
                timer.clock.start();
                continue;
            }

            timer.clock.update();

            if (!timer.pass_delay) {
                if (timer.clock.progress > input_sys.key_repeat_state.delay) {
                    timer.pass_delay = true;
                    timer.clock.restart();
                }
            }
            else if (timer.clock.progress > input_sys.key_repeat_state.rate) {
                input_sys.process_key(i, true);
                timer.clock.restart();
            }
       } else {
            KeyRepeatTimer* timer = &input_sys.key_repeat_timers[i];
            timer.clock.stop();
            timer.pass_delay = false;
       }
    }
}

// ----- Keyboard input ------

fn bool InputSystem.is_key_down(&input_sys, uint key) @inline
{
    return input_sys.kb_curr[key];
}

fn bool InputSystem.is_key_up(&input_sys, uint key) @inline
{
    return !input_sys.kb_curr[key];
}

fn bool InputSystem.was_key_down(&input_sys, uint key) @inline
{
    return input_sys.kb_prev[key];
}

fn bool InputSystem.was_key_up(&input_sys, uint key) @inline
{
    return !input_sys.kb_prev[key];
}

fn void InputSystem.process_key(&input_sys, uint key, bool is_pressed)
{
    input_sys.kb_curr[key] = is_pressed;
    EventContext context @noinit;
    context.u32[0] = key;
    input_sys.app.event_sys.execute_handlers_for_event(is_pressed ? KEY_DOWN : KEY_UP, context, &input_sys.app.vk_ctx.renderer);
}

// ----- Mouse input ------

fn bool InputSystem.is_button_down(&input_sys, MouseButton button) @inline
{
    return input_sys.mouse_curr.buttons[button];
}

fn bool InputSystem.is_button_up(&input_sys, MouseButton button) @inline
{
    return !input_sys.mouse_curr.buttons[button];
}

fn bool InputSystem.was_button_down(&input_sys, MouseButton button) @inline
{
    return input_sys.mouse_prev.buttons[button];
}

fn bool InputSystem.was_button_up(&input_sys, MouseButton button) @inline
{
    return !input_sys.mouse_prev.buttons[button];
}

fn bool MousePos.eq(MousePos first, MousePos sec) @operator(==)
{
    return first.x == sec.x && first.y == sec.y;
}

fn MousePos InputSystem.get_mouse_position(&input_sys) @inline
{
    return input_sys.mouse_curr.pos;
}

fn MousePos InputSystem.get_previous_mouse_position(&input_sys) @inline
{
    return input_sys.mouse_prev.pos;
}

fn void InputSystem.process_mouse_button(&input_sys, MouseButton button, bool is_pressed)
{
    input_sys.mouse_curr.buttons[button] = is_pressed;
    EventContext context @noinit;
    context.u32[0] = button;
    input_sys.app.event_sys.execute_handlers_for_event(
        is_pressed ? MOUSE_DOWN : MOUSE_UP, context, &input_sys.app.vk_ctx.renderer
    );
}

fn void InputSystem.process_mouse_move(&input_sys, MousePos pos)
{
    if (@unlikely(!input_sys.accept_move_events)) {
        return;
    }

    static bool first_mouse_move = true;

    if (@unlikely(first_mouse_move)) {
        input_sys.mouse_curr.pos = pos;
        first_mouse_move = false;
        return;
    }

    input_sys.mouse_curr.pos = pos;
    input_sys.mouse_delta.x = input_sys.mouse_curr.pos.x - input_sys.mouse_prev.pos.x;
    input_sys.mouse_delta.y = input_sys.mouse_curr.pos.y - input_sys.mouse_prev.pos.y;

    EventContext context @noinit;
    context.f32[0] = input_sys.mouse_delta.x;
    context.f32[1] = input_sys.mouse_delta.y;
    input_sys.app.event_sys.execute_handlers_for_event(MOUSE_MOVE, context, &input_sys.app.vk_ctx.renderer);
}

fn void InputSystem.process_mouse_wheel(&input_sys, bool z_delta)
{
    EventContext context @noinit;
    context.b8[0] = z_delta;
    input_sys.app.event_sys.execute_handlers_for_event(MOUSE_WHEEL, context, &input_sys.app.vk_ctx.renderer);
}
