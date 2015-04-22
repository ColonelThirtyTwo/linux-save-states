
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#define TESTSTRING ("Hello world, this is a test")

int main() {
	char* buffer = malloc(1024);
	memcpy(buffer, TESTSTRING, sizeof(TESTSTRING));
	
	printf("Copied %d bytes\n", (int)sizeof(TESTSTRING));
	printf("PID: %d\n", getpid());
	kill(getpid(), SIGSTOP);
	return 0;
}
