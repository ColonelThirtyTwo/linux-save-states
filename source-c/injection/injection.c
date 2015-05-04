
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/syscall.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

#define TRACEE_READ_FD 500
#define TRACEE_WRITE_FD 501

typedef enum {
	#include "wrapper2appcmds"
	W2AC_END
} Wrapper2AppCmd;

typedef enum {
	#include "app2wrappercmds"
	A2WC_END
} App2WrapperCmd;

/// Writes a message to stderr and aborts the process.
static void fail(const char* arg) {
	fprintf(stderr, "%s: %s\n", arg, strerror(errno));
	abort();
}

/// Reads a value from the specified file descriptor and calls fail on errors.
static void readData(int fd, void* out, size_t size) {
	ssize_t numRead = read(fd, out, size);
	if(numRead == -1)
		fail("read failed");
	assert(numRead == size);
}

/*static void writeData(int fd, const void* in, size_t size) {
	ssize_t numWritten = write(fd, in, size);
	if(numWritten == -1)
		fail("write failed");
	assert(numWritten == size);
}*/

/// Gets the process PID directly from the kernel, bypassing any caching that libc might be doing.
static pid_t real_getpid() {
	pid_t pid;
	__asm__ volatile (
		"syscall;"
		: "=a" (pid)
		: "0" (SYS_getpid)
	);
	return pid;
}

/// Pauses the process and waits for the tracer to resume it.
/// The game's state can be saved during this pause.
void lss_pause() {
	while(1) {
		// Pause self (and notify tracer that we finished a command)
		if(kill(real_getpid(), SIGTRAP) == -1)
			fail("kill failed");
		
		// Get a command
		int32_t cmdInt;
		readData(TRACEE_READ_FD, &cmdInt, sizeof(int32_t));
		Wrapper2AppCmd cmd = (Wrapper2AppCmd) cmdInt;
				
		if(cmd == CMD_CONTINUE)
			return;
		else if(cmd == CMD_SETHEAP) {
			void* newPtr;
			readData(TRACEE_READ_FD, &newPtr, sizeof(void*));
			
			int code = brk(newPtr);
			if(code == -1)
				fail("brk failed");
		} else if(cmd == CMD_OPEN) {
			// Read filename
			uint32_t fnameLen;
			readData(TRACEE_READ_FD, &fnameLen, sizeof(fnameLen));
			
			char fname[fnameLen+1];
			readData(TRACEE_READ_FD, fname, fnameLen);
			fname[fnameLen] = 0;
			
			// Read destination file descriptor
			int fd;
			readData(TRACEE_READ_FD, &fd, sizeof(int));
			
			// Read flags and seek position
			int flags;
			readData(TRACEE_READ_FD, &flags, sizeof(int));
			
			uint64_t seekPos;
			readData(TRACEE_READ_FD, &seekPos, sizeof(uint64_t));
			
			// Open the file to some arbitrary FD
			int tempFd = open(fname, flags);
			if(tempFd == -1)
				fail("open failed");
			
			// Move FD to the one we want.
			if(tempFd != fd) {
				if(dup2(tempFd, fd) == -1)
					fail("dup2 failed");
				if(close(tempFd) == -1)
					fail("close failed");
			}
			
			// Seek
			off_t seekedPos = lseek(fd, seekPos, SEEK_SET);
			if(seekedPos == -1)
				fail("seek failed");
			assert(seekedPos == seekPos);
		} else if(cmd == CMD_CLOSE) {
			int fd;
			readData(TRACEE_READ_FD, &fd, sizeof(int));
			
			if(close(fd) == -1)
				fail("close failed");
		} else {
			fprintf(stderr, "Unknown command: %x\n", cmdInt);
			abort();
		}
	}
}
