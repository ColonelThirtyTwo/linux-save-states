
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

extern void lss_pause(void);

#define TESTSTRING ("Hello world, this is a test")
static char somestring[1024] = TESTSTRING;

int main() {
	char* buffer = malloc(1024);
	memcpy(buffer, TESTSTRING, sizeof(TESTSTRING));
	
	printf("PID: %d\n", getpid());
	lss_pause();
	
	printf("Heap String: %s\n", buffer);
	printf("Stack String: %s\n", somestring);
	
	return 0;
}
