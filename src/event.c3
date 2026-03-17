module engine;

import std::collections::elastic_array;

const MAX_EVENT_CNT = 100u;

struct EventSystem
{
	EventHandlerList[EventCode.len] handlers;
}

// NOTE: first two events are the same value as glfw
// Don't reorder
enum EventCode : inline uint
{
	MOUSE_DOWN,
	MOUSE_UP,
	MOUSE_MOVE,
	MOUSE_WHEEL,
	KEY_DOWN,
	KEY_UP,
	RESIZE,
}

union EventContext
{
    ulong[2]    u64;
    long[2]     i64;
    double[2]   f64;
    uint[4]     u32;
    int[4]      i32;
    float[4]    f32;
    ushort[8]   u16;
    short[8]    i16;
    char[16]    u8;
    ichar[16]   i8;
	bool[16]    b8;
}

// if returns true, dont proceed with calls to other handlers (event has been handled)
alias EventHandlerFn = fn bool(EventContext ctx, void* listener);
alias EventHandlerList = ElasticArray{EventHandlerFn, MAX_EVENT_CNT};

<*
	@require handler != null : "handler should be valid pointer"
*>
fn void EventSystem.add_event_handler(&event_sys, EventCode code, EventHandlerFn handler)
{
	event_sys.handlers[code].push(handler);
}

fn void EventSystem.execute_handlers_for_event(&event_sys, EventCode code, EventContext ev_ctx, void* listener)
{
	foreach (handler : event_sys.handlers[code]) {
		if (handler(ev_ctx, listener)) {
			break;
		}
	}
}

<*
	@require handler != null : "handler should be valid pointer"
*>
fn void EventSystem.remove_event_handler(&event_sys, EventCode code, EventHandlerFn handler)
{
	foreach (uint ind, curr_handler : event_sys.handlers[code]) {
		if (handler == curr_handler) {
			event_sys.handlers[code].remove_unordered(ind);
		}
	}
}

fn void EventSystem.reset_state(&event_sys)
{
	foreach (&handler_list : event_sys.handlers) {
		handler_list.clear();
	}
}

fn void EventSystem.reset_state_for_event(&event_sys, EventCode code)
{
	event_sys.handlers[code].clear();
}
