
#include <stdio.h>
#include <signal.h>
#include <unistd.h>

int main() {
	printf("PID: %d\n", getpid());
	kill(getpid(), SIGSTOP);
	return 0;
}
