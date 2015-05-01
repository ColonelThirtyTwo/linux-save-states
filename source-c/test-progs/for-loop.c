
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

void lss_pause();

int main() {
	printf("PID: %d\n", getpid());
	
	for(int i=0; i<5; i++) {
		printf("i = %d\n", i);
		//kill(getpid(), SIGSTOP);
		lss_pause();
	}
	
	return 0;
}

