module event;

import std::collections::elastic_array;

const MAX_EVENT_CNT = 100u;

enum EventCode : uint
{
	MOUSE_MOVE,
	MOUSE_DOWN,
	MOUSE_UP,
	MOUSE_WHEEL,
	KEY_DOWN,
	KEY_UP,
	RESIZE,
	_COUNT
}

union EventContext
{
    ulong[2]  u64;
    long[2]   i64;
    double[2] f64;
    uint[4]   u32;
    int[4]    i32;
    float[4]  f32;
    ushort[8] u16;
    short[8]  i16;
    char      u8;
    ichar     i8;
}

// if returns true, dont proceed with calls to other listeners (event has been handled)
alias OnEventFn = fn bool(EventContext*);
alias EventList = ElasticArray{Event, MAX_EVENT_CNT};

struct Event
{
	EventCode  code;
	OnEventFn  callback;
}

struct EventSystem
{
	ElasticArray{EventList, (uint)EventCode._COUNT} event_lists;
}

<*
	@require (uint)ev.code < event_sys.event_lists.size : "Should be in bounds"
	@require ev.callback != null
*>
fn void EventSystem.set_event(&event_sys, Event ev)
{
	event_sys.event_lists[(uint)ev.code].push(ev);
}

<*
	@require (uint)code < event_sys.event_lists.size : "Should be in bounds"
*>
fn void EventSystem.execute_event_listeners(&event_sys, EventCode code, EventContext* ev_ctx)
{
	foreach (ev : event_sys.event_lists[(uint)code]) {
		if (ev.callback(ev_ctx)) {
			break;
		}
	}
}

<*
	@require (uint)code < event_sys.event_lists.size : "Should be in bounds"
	@require callback != null
*>
fn void EventSystem.remove_event(&event_sys, EventCode code, OnEventFn callback)
{
	EventList* ev_list = &event_sys.event_lists[(uint)code];
	foreach (uint ind, ev : ev_list) {
		if (ev.callback == callback) {
			event_sys.event_lists[(uint)code].remove_unordered(ind);
		}
	}
}

fn void EventSystem.reset_state(&event_sys)
{
	foreach (&ev_list : event_sys.event_lists) {
		ev_list.clear();
	}
}
