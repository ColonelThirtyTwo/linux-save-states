
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <errno.h>
#include <string.h>

extern void lss_pause(void);

int main() {
	#define ULL unsigned long long
	
	for(int i=0; i<5; i++) {
		struct timespec realtime;
		struct timespec monotonic;
		if(clock_gettime(CLOCK_REALTIME, &realtime) != 0) {
			fprintf(stderr, "error getting realtime: %s", strerror(errno));
			return 1;
		}
		if(clock_gettime(CLOCK_MONOTONIC, &monotonic) != 0) {
			fprintf(stderr, "error getting monotonic: %s", strerror(errno));
			return 1;
		}
		
		printf("Realtime: %llu s %llu ns\n", (ULL)realtime.tv_sec, (ULL)realtime.tv_nsec);
		printf("Monotonic: %llu s %llu ns\n", (ULL)monotonic.tv_sec, (ULL)monotonic.tv_nsec);
		lss_pause();
	}
	
	return 0;
}
