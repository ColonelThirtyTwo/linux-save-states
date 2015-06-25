
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

extern void lss_pause(void);
extern void lss_test_command(uint32_t data);

int main() {
	printf("PID: %d\n", getpid());
	
	for(int i=0; i<5; i++) {
		printf("i = %d\n", i);
		lss_test_command(i);
		//lss_pause();
	}
	
	return 0;
}
