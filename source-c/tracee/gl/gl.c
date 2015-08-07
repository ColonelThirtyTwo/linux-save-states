
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
