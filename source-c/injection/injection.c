
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/syscall.h>

#define _SIGNAL_H
#include <asm-generic/signal-defs.h>
#include <bits/siginfo.h>
#include <bits/signum.h>
#include <bits/sigaction.h>
#include <linux/fs.h>
#include <sys/mman.h>

#include "tracee.h"

#ifdef __x86_64__
	#include "syscalls.x64.c"
#else
	#include "syscalls.i86.c"
#endif

TraceeData* traceeData = NULL;

/// raise implementation, taken from musl
static int raise(int sig)
{
	unsigned long all_mask[] = {
		#if ULONG_MAX == 0xffffffff && _NSIG == 129
			-1UL, -1UL, -1UL, -1UL
		#elif ULONG_MAX == 0xffffffff
			-1UL, -1UL
		#else
			-1UL
		#endif
	};
	
	int tid, ret;
	sigset_t set;
	syscall4(SYS_rt_sigprocmask, SIG_BLOCK, &all_mask, &set, _NSIG/8);
	tid = syscall0(SYS_gettid);
	ret = syscall2(SYS_tkill, tid, sig);
	syscall4(SYS_rt_sigprocmask, SIG_SETMASK, &set, 0, _NSIG/8);
	return ret;
}

/// abort implementation, taken from musl
__attribute__((noreturn)) static void abort() {
	raise(SIGABRT);
	raise(SIGKILL);
	while(1) {}
}

__attribute__((noreturn)) void fail(const char* msg) {
	size_t len = 0;
	while(msg[len++] != 0);
	
	syscall3(SYS_write, 2, "lss: ", sizeof("lss: ")-1);
	syscall3(SYS_write, 2, msg, len-1);
	syscall3(SYS_write, 2, "\n", 1);
	
	abort();
}

/// Reads a value from the specified file descriptor and aborts on errors.
static void readData(int fd, void* out, size_t size) {
	ssize_t numRead = syscall3(SYS_read, fd, out, size);
	if(numRead != size)
		fail("could not read from the command pipe");
}

/// Called at startup
void init() {
	if(traceeData != NULL)
		return;
	
	traceeData = (void*) syscall6(SYS_mmap, NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, 0, 0);
	if(traceeData == MAP_FAILED)
		fail("could not allocate tracee data");
	
	traceeData->version = TRACEE_DATA_VERSION;
	
	syscall3(SYS_write, 2, "lss debug: initialized\n", sizeof("lss debug: initialized\n")-1);
}

/// Processes one command from the command pipe
int doOneCommand() {
	// Get a command
	int32_t cmdInt;
	readData(TRACEE_READ_FD, &cmdInt, sizeof(int32_t));
	Wrapper2AppCmd cmd = (Wrapper2AppCmd) cmdInt;
			
	if(cmd == CMD_CONTINUE)
		return 1;
	else if(cmd == CMD_SETHEAP) {
		void* brkPtr;
		readData(TRACEE_READ_FD, &brkPtr, sizeof(void*));
		
		void* newBrk = (void*) syscall1(SYS_brk, brkPtr);
		if(newBrk < brkPtr)
			fail("could not set program break");
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
		int tempFd = syscall2(SYS_open, fname, flags);
		if(tempFd < 0)
			fail("could not open saved file descriptor");
		
		// Move FD to the one we want.
		if(tempFd != fd) {
			if(syscall2(SYS_dup2, tempFd, fd) < 0)
				fail("could not move saved file descriptor");
			if(syscall1(SYS_close, tempFd) < 0)
				fail("could not close temporary file descriptor");
		}
		
		// Seek
		off_t seekedPos = syscall3(SYS_lseek, fd, seekPos, SEEK_SET);
		if(seekedPos != seekPos)
			fail("could not seek file");
	} else if(cmd == CMD_CLOSE) {
		int fd;
		readData(TRACEE_READ_FD, &fd, sizeof(int));
		
		if(syscall1(SYS_close, fd) < 0)
			fail("could not close file");
	} else if(cmd == CMD_SETCLOCK) {
		int type;
		uint64_t seconds, nanoseconds;
		readData(TRACEE_READ_FD, &type, sizeof(type));
		readData(TRACEE_READ_FD, &seconds, sizeof(seconds));
		readData(TRACEE_READ_FD, &nanoseconds, sizeof(nanoseconds));
		
		if(type == CLOCK_REALTIME) {
			traceeData->clocks.realtime.tv_sec = seconds;
			traceeData->clocks.realtime.tv_nsec = nanoseconds;
		} else if(type == CLOCK_MONOTONIC) {
			traceeData->clocks.monotonic.tv_sec = seconds;
			traceeData->clocks.monotonic.tv_nsec = nanoseconds;
		} else {
			fail("unrecognized clock type");
		}
	} else if(cmd == CMD_SETTIME) {
		uint64_t timestamp;
		readData(TRACEE_READ_FD, &timestamp, sizeof(timestamp));
		
		traceeData->clocks.timestamp = timestamp;
	} else {
		fail("unrecognized command");
	}
	return 0;
}
