
#include <stddef.h>
#include <GL/gl.h>
#include <GL/glext.h>

#include "tracee.h"
#include "gl/gl.h"
#include "gl/buffer.h"

EXPORT void glFlush() {
	int cmd = 9001;
	queueGlCommand(&cmd, sizeof(cmd));
	flushGlBuffer();
}

EXPORT void glGetBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size, void *data) {
	struct {
		int cmd;
		GLenum target;
		GLintptr offset;
		GLsizeiptr size;
	} __attribute__((packed)) params;
	
	params.cmd = 9002;
	params.target = target;
	params.offset = offset;
	params.size = size;
	
	queueGlCommand(&params, sizeof(params));
	flushGlBuffer();
	readData(TRACEE_GL_READ_FD, data, size);
}
