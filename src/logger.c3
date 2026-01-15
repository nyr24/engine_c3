module logger;

import std::io;

enum LogLevel {
	INFO,
	DEBUG,
	TRACE,
	WARN,
	ERROR,
	FATAL
}

// TODO: colored mode

fn void log_inner(LogLevel level, String fmt, args...) @private
{
	if (level < LogLevel.WARN) {
		io::printf(fmt, args);
	} else {
		io::eprintf(fmt, args);
	}
}

fn void logn_inner(LogLevel level, String fmt, args...) @private
{
	if (level < LogLevel.WARN) {
		io::printfn(fmt, args);
	} else {
		io::eprintfn(fmt, args);
	}
}

macro @log(LogLevel #level, String fmt, args...)
{
	$if ($feature(SF_DEBUG)):
		log_inner(#level, fmt, args);
	$else
		$if	(#level >= LogLevel.ERROR):
			log_inner(#level, fmt, args);
		$endif
	$endif
}

macro @logn(LogLevel #level, String fmt, args...)
{
	$if ($feature(SF_DEBUG)):
		logn_inner(#level, fmt, args);
	$else
		$if	(#level >= LogLevel.ERROR):
			logn_inner(#level, fmt, args);
		$endif
	$endif
}
