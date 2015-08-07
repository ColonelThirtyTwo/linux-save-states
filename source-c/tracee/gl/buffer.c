
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/syscall.h>
#include <sys/mman.h>

#ifdef __x86_64__
	#include "syscalls.x64.c"
#else
	#include "syscalls.i86.c"
#endif

#include "tracee.h"
#include "gl/gl.h"

/// Initializes the GL command stream buffer.
void initGlBuffer(void) {
	traceeData->gl.buffer = (void*) syscall6(
		SYS_mmap, NULL, LSS_GL_BUFFER_SIZE, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, 0, 0);
	if(traceeData->gl.buffer == MAP_FAILED)
		fail("could not allocate gl commands buffer");
	
	traceeData->gl.bufferEnd = 0;
}

void queueGlCommand(const void* cmd, size_t len) {
	if(len > LSS_GL_BUFFER_SIZE - traceeData->gl.bufferEnd) {
		// buffer filled, flush it
		flushGlBuffer();
		
		if(len > LSS_GL_BUFFER_SIZE) {
			// Too big for the buffer
			writeData(TRACEE_GL_WRITE_FD, cmd, len);
			return;
		}
	}
	
	__builtin_memcpy(traceeData->gl.buffer+traceeData->gl.bufferEnd,
		cmd, len);
	traceeData->gl.bufferEnd += len;
}

void flushGlBuffer(void) {
	writeData(TRACEE_GL_WRITE_FD, traceeData->gl.buffer, traceeData->gl.bufferEnd);
	traceeData->gl.bufferEnd = 0;
}

