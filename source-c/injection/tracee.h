
#ifndef _TRACEE_H
#define _TRACEE_H

#include <stdint.h>
#include <bits/time.h>

#define TRACEE_DATA_VERSION 1
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


/// Data used by the tracee and overwritten functions
typedef struct {
	/// Version of the data. May be different than TRACEE_DATA_VERSION if an old state is loaded.
	uint64_t version;
	
	struct {
		struct timeval realtime;
		struct timeval monotonic;
	} clocks;
} TraceeData;

extern TraceeData* traceeData;

/// Pauses the program, allowing the state to be saved, and reads commands from the tracer.
__attribute__((visibility("default"))) void lss_pause(void);

/// Prints msg to stderr and aborts the process.
__attribute__((noreturn)) void fail(const char* msg);

#endif
