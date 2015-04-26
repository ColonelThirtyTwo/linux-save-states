
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

int main() {
	printf("PID: %d\n", getpid());
	
	for(int i=0; i<4; i++) {
		printf("i = %d\n", i);
		kill(getpid(), SIGSTOP);
	}
	
	return 0;
}

