
#include <stddef.h>
#include <errno.h>
#include <time.h>
#include <sys/time.h>

#include "tracee.h"

#pragma GCC visibility push(default)

// Lots of function parameters that are required to be there for ABI compatibility, but we don't care about.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"

int clock_getres(clockid_t clk_id, struct timespec *res) {
	if(res == NULL)
		return 0;
	
	res->tv_sec = 0;
	res->tv_nsec = 1;
	
	return 0;
}

int clock_gettime(clockid_t clk_id, struct timespec *tp) {
	if(tp == NULL)
		return 0;
	
	if(clk_id == CLOCK_REALTIME) {
		tp->tv_sec = traceeData->clocks.realtime.tv_sec;
		tp->tv_nsec = traceeData->clocks.realtime.tv_nsec;
	} else if(clk_id == CLOCK_MONOTONIC) {
		tp->tv_sec = traceeData->clocks.monotonic.tv_sec;
		tp->tv_nsec = traceeData->clocks.monotonic.tv_nsec;
	} else {
		tp->tv_sec = 0;
		tp->tv_nsec = 0;
	}
	return 0;
}

int clock_settime(clockid_t clk_id, const struct timespec *tp) {
	return EPERM;
}

time_t time(time_t *t) {
	return traceeData->clocks.realtime.tv_sec;
}

int gettimeofday(struct timeval* tv, struct timezone* tz) {
	if(tv != NULL) {
		tv->tv_sec = traceeData->clocks.realtime.tv_sec;
		tv->tv_usec = traceeData->clocks.realtime.tv_nsec / 1000;
	}
	if(tz != NULL) {
		tz->tz_minuteswest = 0;
		tz->tz_dsttime = 0; //DST_NONE;
	}
	
	return 0;
}

int settimeofday(const struct timeval* tv, const struct timezone* tz) {
	return EPERM;
}

#pragma GCC visibility pop
#pragma GCC diagnostic pop
