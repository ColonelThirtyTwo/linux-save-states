
#include <stddef.h>
#include <errno.h>
#include <time.h>

#include "tracee.h"

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
		tp->tv_sec = traceeData->clocks.realtime.tv_sec;
		tp->tv_nsec = traceeData->clocks.realtime.tv_nsec;
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
	return traceeData->clocks.timestamp;
}
