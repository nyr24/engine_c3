module logger;

import std::io;
import std::collections::elastic_array;

enum LogLevel : uint
{
	INFO,
	DEBUG,
	TRACE,
	TEST,
	WARN,
	ERROR,
	FATAL,
	_COUNT
}

const BUFF_LEN = 512;
const MSG_BUFF_LEN = 480;

String[(uint)LogLevel._COUNT] color_strings = {
    "\x1b[1;32",
    "\x1b[1;34",
    "\x1b[1;28",
    "\x1b[45;37",
    "\x1b[1;33",
    "\x1b[1;31",
    "\x1b[0;41",
};

String[(uint)LogLevel._COUNT] log_level_as_str = {
    "[INFO]: ",
    "[DEBUG]: ",
    "[TRACE]: ",
    "[TEST]: ",
    "[WARN]: ",
    "[ERROR]: ",
    "[FATAL]: ",
};

macro void log_inner(LogLevel level, bool $newline, String $fmt, args...) @private
{
	char[BUFF_LEN] buff;
	char[MSG_BUFF_LEN] msg_buff;
	char[] msg_view = io::bprintf(msg_buff[..], $fmt, args)!!;
	char[] log_view = io::bprintf(buff[..], "\x1b[%sm%s%s\x1b[0m", color_strings[(uint)level], log_level_as_str[(uint)level], (String)msg_view)!!;

	$if !$newline:
		if (level < LogLevel.WARN) {
			io::printf("%s", (String)log_view);
		} else {
			io::eprintf("%s", (String)log_view);
		}
	$else
		if (level < LogLevel.WARN) {
			io::printfn("%s", (String)log_view);
		} else {
			io::eprintfn("%s", (String)log_view);
		}
	$endif
}

macro @log(LogLevel #level, String $fmt, args...)
{
	$if ($feature(SF_DEBUG)):
		log_inner(#level, false, $fmt, args);
	$else
		$if	(#level >= LogLevel.ERROR):
			log_inner(#level, false, $fmt, args);
		$endif
	$endif
}

macro @logn(LogLevel #level, String $fmt, args...)
{
	$if ($feature(SF_DEBUG)):
		log_inner(#level, true, $fmt, args);
	$else
		$if	(#level >= LogLevel.ERROR):
			log_inner(#level, true, $fmt, args);
		$endif
	$endif
}

fn void log_test() @test
{
	log_inner(LogLevel.INFO, true, "%s log", "info");
	log_inner(LogLevel.DEBUG, true, "%s log", "debug");
	log_inner(LogLevel.TRACE, true, "%s log", "trace");
	log_inner(LogLevel.TEST, true, "%s log", "test");
	log_inner(LogLevel.WARN, true, "%s log", "warn");
	log_inner(LogLevel.ERROR, true, "%s log", "error");
	log_inner(LogLevel.FATAL, true, "%s log", "fatal");
}
