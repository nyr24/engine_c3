module engine;

import std::time;
// NOTE: DEBUG
import logger;

alias NanoTimeStamp = time::Clock;

const double US_AMOUNT_IN_1_SECOND = 1_000_000_000.0;
const double US_AMOUNT_IN_1_SECOND_INV = 1 / 1_000_000_000.0;

// tracks initial timestamp
struct TimepointClock
{
    NanoTimeStamp 	start_point;
    NanoDuration 	progress;
}

fn void TimepointClock.start(&clock)
{
    clock.start_point = clock::now();
    clock.progress = time::NANO_DURATION_ZERO;
}

<*
	@require clock.is_running() : "Should be running"
*>
fn NanoDuration TimepointClock.update_and_get_delta(&clock)
{
	NanoDuration new_progress = clock.start_point.to_now();
	NanoDuration delta = new_progress - clock.progress;
	clock.progress = new_progress;
	return delta;
}

<*
	@require clock.is_running() : "Should be running"
*>
fn void TimepointClock.update(&clock)
{
    clock.progress = clock.start_point.to_now();
}

fn void TimepointClock.stop(&clock)
{
    clock.start_point = (NanoTimeStamp)0;
    clock.progress = time::NANO_DURATION_ZERO;
}

fn void TimepointClock.restart(&clock)
{
	clock.start_point = (NanoTimeStamp)0;
    clock.start();
}

fn bool TimepointClock.is_running(&clock) @inline
{
    return clock.start_point > (NanoTimeStamp)0;
}

// --- DeltaClock

// tracks delta time
struct DeltaClock
{
    NanoTimeStamp 	timestamp;
    NanoDuration	delta;
}

fn void DeltaClock.start(&clock)
{
	clock.timestamp = clock::now();
	clock.delta = (NanoDuration)0;
}

fn NanoDuration DeltaClock.update_and_get_delta(&clock)
{
	NanoTimeStamp new_timestamp = clock::now();
	clock.delta = new_timestamp - clock.timestamp;
	clock.timestamp = new_timestamp;
	return clock.delta;
}

fn void DeltaClock.update(&clock)
{
	NanoTimeStamp new_timestamp = clock::now();
	clock.delta = new_timestamp - clock.timestamp;
	clock.timestamp = new_timestamp;
}

fn void DeltaClock.stop(&clock)
{
    clock.timestamp = (NanoTimeStamp)0;
    clock.delta = (NanoDuration)0;
}

fn void DeltaClock.restart(&clock)
{
	clock.stop();
    clock.start();
}

fn bool DeltaClock.is_running(&clock) @inline
{
    return clock.timestamp > (NanoTimeStamp)0;
}

fn double DeltaClock.get_delta_time_sec(&clock)
{
	return (double)clock.delta * US_AMOUNT_IN_1_SECOND_INV;
}
