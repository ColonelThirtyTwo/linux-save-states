/// Commands for getting and setting the traced process' clock.
module commands.time;

import std.stdio;
import std.datetime;
import std.range;
import std.algorithm;
import std.conv;

import savefile;
import commands;
import global;

@("")
@("Gets the current time as the tracee process sees it.")
@ShellOnly
int cmd_get_time(string[] args) {
	mixin(ARG_HELP!cmd_get_time);
	mixin(ARG_NUM_REQUIRED!(cmd_get_time, 0));
	
	auto date = SysTime(unixTimeToStdTime(process.time.realtime.sec));
	
	writeln("Realtime clock: ", process.time.realtime.sec ," s + ", process.time.realtime.nsec, " ns (", date, ")");
	writeln("Monotonic clock: ", process.time.monotonic.sec, " s ", process.time.monotonic.nsec, " ns");
	writeln("Time per frame: ", process.time.timePerFrame, " ns");
	
	return 0;
}

@("realtime|monotonic <seconds> <nanoseconds>")
@(`Sets current time as the tracee process sees it.
Note that the time-per-frame will still be added to this value after continuing execution.`)
@ShellOnly
int cmd_set_time(string[] args) {
	mixin(ARG_HELP!cmd_set_time);
	mixin(ARG_NUM_REQUIRED!(cmd_set_time, 3));
	
	ulong seconds, nanoseconds;
	try {
		seconds = to!ulong(args[1]);
		nanoseconds = to!ulong(args[2]);
	} catch(ConvException ex) {
		stderr.writeln("Invalid number");
		return 1;
	}
	
	if(args[0] == "realtime") {
		process.time.realtime.sec = seconds;
		process.time.realtime.nsec = nanoseconds;
	} else if(args[0] == "monotonic") {
		process.time.monotonic.sec = seconds;
		process.time.monotonic.nsec = nanoseconds;
	} else {
		stderr.writeln("Invalid clock type");
		return 1;
	}
	
	return 0;
}

@("<nanoseconds>")
@("Sets the amount of time to increment the clock on each frame.")
@ShellOnly
int cmd_set_time_per_frame(string[] args) {
	mixin(ARG_HELP!cmd_set_time_per_frame);
	mixin(ARG_NUM_REQUIRED!(cmd_set_time_per_frame, 1));
	
	ulong tpf;
	
	try {
		tpf = to!ulong(args[0]);
	} catch(ConvException ex) {
		stderr.writeln("Invalid number");
		return 1;
	}
	
	mixin(Transaction!saveFile);
	
	process.time.timePerFrame = tpf;
	saveFile["timePerFrame"] = tpf;
	
	return 0;
}
