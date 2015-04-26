
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

#define TESTSTRING ("Hello world, this is a test\n")

int main() {
	char* buffer = malloc(1024);
	memcpy(buffer, TESTSTRING, sizeof(TESTSTRING));
	
	printf("PID: %d\n", getpid());
	kill(getpid(), SIGSTOP);
	
	printf("%s", buffer);
	
	return 0;
}
