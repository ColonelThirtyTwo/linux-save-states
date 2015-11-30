#define GL_GLEXT_PROTOTYPES 1

#include <stdlib.h>
#include <stdio.h>
#include <X11/Xlib.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <GL/glx.h>
#include <assert.h>
#include <unistd.h>
#include <stdint.h>

#include "common.c"

static const uint8_t testdata[256] = {1,2,3};

int main() {
	struct {
		int cmd;
		GLenum target;
		GLintptr offset;
		GLsizeiptr size;
	} __attribute__((packed)) params;
	printf("Params size: %zu\n", sizeof(params));
	
	Display* display;
	Window window;
	GLXContext context;
	printf("Creating context.\n");
	createContext(&display, &window, &context);
	
	printf("Generating buffer.\n");
	GLuint buf;
	glGenBuffers(1, &buf);
	assert(buf != 0);
	printf("id = %u\n", buf);
	
	printf("Uploading data\n");
	glBindBuffer(GL_ARRAY_BUFFER, buf);
	glBufferData(GL_ARRAY_BUFFER, 256, testdata, GL_STATIC_DRAW);
	
	printf("Fetching data\n");
	uint8_t fetched[256];
	glGetBufferSubData(GL_ARRAY_BUFFER, 0, 256, fetched);
	printf("Fetched, checking\n");
	for(int i=0; i<sizeof(testdata)/sizeof(testdata[0]); i++)
		assert(fetched[i] == testdata[i]);
	
	printf("Deleting.\n");
	glDeleteBuffers(1, &buf);
	glFlush();
	
	printf("Closing.\n");
	destroyContext(display, window, context);
}
