
#include <stdlib.h>
#include <stdio.h>
#include <X11/Xlib.h>
#include <GL/glx.h>
#include <assert.h>
#include <unistd.h>

extern void lss_pause(void);

int main() {
	printf("Pre-open\n");
	lss_pause();
	
	Display* display = XOpenDisplay(NULL);
	assert(display != NULL);
	
	int screen = DefaultScreen(display);
	Window root = RootWindow(display, screen);
	
	int attribs[1] = {None};
	
	XVisualInfo* visinfo = glXChooseVisual(display, screen, attribs);
	assert(visinfo != NULL);
	
	XSetWindowAttributes attr;
	attr.colormap = XCreateColormap(display, root, visinfo->visual, AllocNone);
	
	Window window = XCreateWindow(display, root, 0, 0, 800, 600, 0, visinfo->depth, InputOutput,
		visinfo->visual, 0, &attr);
	
	{
		XSizeHints sizehints;
		sizehints.x = 0;
		sizehints.y = 0;
		sizehints.width  = 800;
		sizehints.height = 600;
		sizehints.flags = USSize | USPosition;
		XSetNormalHints(display, window, &sizehints);
		XSetStandardProperties(display, window, "", "", None, NULL, 0, &sizehints);
	}
	
	GLXContext context = glXCreateContext(display, visinfo, NULL, True);
	assert(context != NULL);
	
	XFree(visinfo);
	
	XMapWindow(display, window);
	glXMakeCurrent(display, window, context);
	
	printf("Window created\n");
	glXSwapBuffers(display, window);
	
	sleep(5);
	
	glXMakeCurrent(display, None, NULL);
	glXDestroyContext(display, context);
	XDestroyWindow(display, window);
	XCloseDisplay(display);
	
	printf("Window closed\n");
	lss_pause();
	
	return 0;
}
