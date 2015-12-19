
#include <stddef.h>
#include <GL/gl.h>
#include <GL/glext.h>

#include "tracee.h"
#include "gl/gl.h"
#include "gl/buffer.h"
#include "gl/gl-generated.h"

EXPORT void glFlush() {
	int cmd = _LSS_GL_glFlush;
	queueGlCommand(&cmd, sizeof(cmd));
	flushGlBuffer();
}

EXPORT void glGetBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size, void *data) {
	struct {
		int cmd;
		GLenum target;
		GLintptr offset;
		GLsizeiptr size;
	} __attribute__((packed)) params = {
		_LSS_GL_glGetBufferSubData,
		target,
		offset,
		size
	};
	
	queueGlCommand(&params, sizeof(params));
	flushGlBuffer();
	readData(TRACEE_GL_READ_FD, data, size);
}

EXPORT void glGetBufferParameteriv(GLenum target, GLenum param, GLint* data) {
	struct {
		int cmd;
		GLenum target;
		GLenum param;
	} __attribute__((packed)) params = {
		_LSS_GL_glGetBufferParameteriv,
		target,
		param
	};
	
	queueGlCommand(&params, sizeof(params));
	flushGlBuffer();
	readData(TRACEE_GL_READ_FD, data, sizeof(GLint));
}
