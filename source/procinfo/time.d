module procinfo.time;

import core.sys.posix.time;

import models;
import procinfo;
import procinfo.cmdpipe;

/// Holds the simulated clocks and their time values.
/// Also manages incrementing the clocks and setting the clocks on the tracee.
struct Time {
	Clock realtime, monotonic;
	ulong timePerFrame;
	
	/// Loads the clocks from a SaveState.
	/// Doesn't update the tracee's clock.
	void loadTime()(in auto ref SaveState state) pure nothrow @nogc {
		realtime = state.realtime;
		monotonic = state.monotonic;
	}
	
	/// Increments all clocks by the given amount of time in nanoseconds.
	/// This handles nanosecond-to-second wraparounds.
	/// Doesn't update the tracee's clock.
	void incrementTime(ulong ns) pure nothrow @nogc {
		// TODO: should probably handle overflow here.
		realtime.nsec += ns;
		monotonic.nsec += ns;
		
		while(realtime.nsec >= 1000000000) {
			realtime.sec += 1;
			realtime.nsec -= 1000000000;
		}
		while(monotonic.nsec >= 1000000000) {
			monotonic.sec += 1;
			monotonic.nsec -= 1000000000;
		}
	}
	
	/// Increments all clocks by one frames worth of time (timePerFrame).
	/// Doesn't update the tracee's clock.
	void incrementFrame() pure nothrow @nogc {
		incrementTime(timePerFrame);
	}
	
	/// Updates the clock on the tracee.
	void updateTime(ProcInfo proc) {
		proc.write(
			Wrapper2AppCmd.CMD_SETCLOCK,
			cast(int) CLOCK_REALTIME,
			realtime.sec,
			realtime.nsec
		);
		proc.write(
			Wrapper2AppCmd.CMD_SETCLOCK,
			cast(int) CLOCK_MONOTONIC,
			monotonic.sec,
			monotonic.nsec
		);
	}
}

unittest {
	Time time;
	time.realtime.sec = 10;
	time.realtime.nsec = 100;
	time.monotonic.sec = 5;
	time.monotonic.nsec = 50000;
	
	time.incrementTime(123);
	
	assert(time.realtime.sec == 10);
	assert(time.realtime.nsec == 223);
	assert(time.monotonic.sec == 5);
	assert(time.monotonic.nsec == 50123);
}

unittest {
	Time time;
	time.realtime.sec = 10;
	time.realtime.nsec = 100;
	time.monotonic.sec = 5;
	time.monotonic.nsec = 50000;
	
	time.incrementTime(1000000001);
	
	assert(time.realtime.sec == 11);
	assert(time.realtime.nsec == 101);
	assert(time.monotonic.sec == 6);
	assert(time.monotonic.nsec == 50001);
}
