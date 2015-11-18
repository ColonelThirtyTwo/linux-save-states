
#include <stdlib.h>
#include <stdio.h>
#include <X11/Xlib.h>
#include <GL/glx.h>
#include <assert.h>
#include <unistd.h>

extern void lss_pause(void);

void createContext(Display** displayOut, Window* windowOut, GLXContext* contextOut) {
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
	
	*displayOut = display;
	*windowOut = window;
	*contextOut = context;
}

void destroyContext(Display* display, Window window, GLXContext context) {
	glXMakeCurrent(display, None, NULL);
	glXDestroyContext(display, context);
	XDestroyWindow(display, window);
	XCloseDisplay(display);
}
