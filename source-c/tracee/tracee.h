
#ifndef _TRACEE_H
#define _TRACEE_H

#include <stdint.h>
#include <sys/types.h>
#include <bits/time.h>

#define EXPORT __attribute__((visibility("default")))

#define TRACEE_DATA_VERSION 1
#define TRACEE_READ_FD 500
#define TRACEE_WRITE_FD 501

#include "x/x-data.h"

/// Commands sent from the tracer to the tracee
typedef enum {
	#include "wrapper2appcmds"
	W2AC_END
} Wrapper2AppCmd;

/// Commands sent from the tracee to the tracer
typedef enum {
	#include "app2wrappercmds"
	A2WC_END
} App2WrapperCmd;

/// Data used by the tracee and overwritten functions
typedef struct {
	/// Version of the data. May be different than TRACEE_DATA_VERSION if an old state is loaded.
	uint64_t version;
	
	/// Clocks for clock_gettime (2). The realtime clock is also used for time (2).
	struct {
		struct timespec realtime;
		struct timespec monotonic;
	} clocks;
	
	lss_x_data x11;
} TraceeData;

extern TraceeData* traceeData;

/// Pauses the program, allowing the state to be saved, and reads commands from the tracer.
EXPORT void lss_pause(void);

/// Prints msg to stderr and aborts the process.
__attribute__((noreturn)) void fail(const char* msg);

/// Reads a value from the specified file descriptor and aborts on errors.
void readData(int fd, void* out, size_t size);
/// Writes a value to the specified file descriptor and aborts on errors.
void writeData(int fd, const void* in, size_t size);

/// String length, including null terminator.
inline size_t str_len(const char* str) {
	size_t len = 0;
	while(str[len++] != 0);
	return len;
}

/// Sends a test command to the tracer.
EXPORT void lss_test_command(uint32_t val);

#endif
