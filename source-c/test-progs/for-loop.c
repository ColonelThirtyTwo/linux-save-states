
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

void lss_pause();

int main() {
	printf("PID: %d\n", getpid());
	
	for(int i=0; i<5; i++) {
		printf("i = %d\n", i);
		lss_pause();
	}
	
	return 0;
}

