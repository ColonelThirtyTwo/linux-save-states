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

extern void lss_pause(void);

static const uint8_t testdata1[256] = {1,2,3};
static const uint8_t testdata2[512] = {6,7,8,9,1,2,3,4};

static void check(GLuint buf, const uint8_t* data, int length) {
	glBindBuffer(GL_ARRAY_BUFFER, buf);
	glBufferData(GL_ARRAY_BUFFER, length, data, GL_STATIC_DRAW);
	
	glFlush();
	lss_pause();
	
	glBindBuffer(GL_ARRAY_BUFFER, buf); // TODO: bindings are not currently saved
	
	printf("Fetching\n");
	int bufSize;
	glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &bufSize);
	uint8_t fetched[length];
	glGetBufferSubData(GL_ARRAY_BUFFER, 0, length, fetched);
	
	printf("Checking\n");
	if(bufSize != length) {
		printf("Size Mismatch: Expected %d bytes, got %d\n", length, bufSize);
	}
	
	for(int i=0; i<length; i++) {
		if(fetched[i] != data[i]) {
			printf("Mismatch: At index %d, expected %d, got %d\n", i, data[i], fetched[i]);
		}
	}
}

int main() {
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
	
	glFlush();
	lss_pause();
	
	// ----------------------------------------------------------
	printf("[] Uploading test data 1\n");
	check(buf, testdata1, sizeof(testdata1));
	
	printf("[] Uploading test data 2\n");
	check(buf, testdata2, sizeof(testdata2));
	
	// ----------------------------------------------------------
	
	printf("Deleting.\n");
	glDeleteBuffers(1, &buf);
	glFlush();
	
	printf("Closing.\n");
	destroyContext(display, window, context);
}
