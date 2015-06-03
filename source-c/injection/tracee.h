
#ifndef _TRACEE_H
#define _TRACEE_H

#define TRACEE_READ_FD 500
#define TRACEE_WRITE_FD 501

/// Pauses the program, allowing the state to be saved, and reads commands from the tracer.
__attribute__((visibility("default"))) void lss_pause(void);

/// Prints msg to stderr and aborts the process.
__attribute__((noreturn)) void fail(const char* msg);

typedef enum {
	#include "wrapper2appcmds"
	W2AC_END
} Wrapper2AppCmd;

typedef enum {
	#include "app2wrappercmds"
	A2WC_END
} App2WrapperCmd;

#endif
