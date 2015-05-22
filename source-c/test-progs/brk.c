
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

void lss_pause();

int main() {
	printf("PID:%d\nCurrent break: %p\n", getpid(), sbrk(0));
	lss_pause();
	
	for(int i=0; i<10; i++) {
		void* p = sbrk(1024);
		snprintf((char*)p, 1024, "Hello world %d\n", i);
		printf("%d Prev break: %p, current break: %p\n", i, p, sbrk(0));
		fflush(stdout);
		
		lss_pause();
		printf("Data in break: %s\n", (char*)p);
	}
	
	return 0;
}
