
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#include <sys/types.h>
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

/// Pauses the process and waits for the tracer to resume it.
/// The game's state can be saved during this pause.
void lss_pause() {
	while(1) {
		// Pause self (and notify tracer that we finished a command)
		kill(getpid(), SIGTRAP);
		
		// Get a command
		int32_t cmdInt;
		readData(TRACEE_READ_FD, &cmdInt, sizeof(int32_t));
		Wrapper2AppCmd cmd = (Wrapper2AppCmd) cmdInt;
		
		// The case statements here have brackets around the code to create new scopes,
		// so that variable names do not clash.
		switch(cmd) {
		case CMD_CONTINUE:
			return;
		case CMD_SETHEAP: {
			void* newPtr;
			readData(TRACEE_READ_FD, &newPtr, sizeof(void*));
			
			int code = brk(newPtr);
			if(code == -1)
				fail("brk failed");
			break;
		} case CMD_OPEN: {
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
			
			break;
		} case CMD_CLOSE: {
			int fd;
			readData(TRACEE_READ_FD, &fd, sizeof(int));
			
			if(close(fd) == -1)
				fail("close failed");
			break;
		} default: {
			fprintf(stderr, "Unknown command: %x\n", cmdInt);
			abort();
		}
		}
	}
}
