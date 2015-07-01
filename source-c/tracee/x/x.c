
#include "tracee.h"
#include "x/x.h"

#define XLIB_ILLEGAL_ACCESS // Lets us access internals of X11 structs
#include <X11/Xlib.h>

#include <GL/glx.h>

#include <stddef.h>
#include <dlfcn.h>

static void initData() {
	#define FILL_ZERO(x) __builtin_memset(&(x), 0, sizeof(x))
	FILL_ZERO(traceeData->x11.display);
	FILL_ZERO(traceeData->x11.screen);
	FILL_ZERO(traceeData->x11.screenDepth);
	FILL_ZERO(traceeData->x11.screenVisual);
	#undef FILL_ZERO
	
	traceeData->x11.display.fd = 499; // arbitrary number
	traceeData->x11.display.screens = &(traceeData->x11.screen);
	traceeData->x11.display.default_screen = 0;
	traceeData->x11.display.nscreens = 1;
	traceeData->x11.display.vendor = (char*)("software"); // Hopefully no one modifies this
	traceeData->x11.display.qlen = 0; // TODO: Update dynamically?
	traceeData->x11.display.proto_major_version = 1;
	traceeData->x11.display.proto_minor_version = 0;
	traceeData->x11.display.release = 1;
	traceeData->x11.display.display_name = (char*)("a:b");
	
	traceeData->x11.screen.display = &(traceeData->x11.display);
	traceeData->x11.screen.root = LSS_X_ROOT_WINDOW;
	traceeData->x11.screen.width = 1920; // TODO: these should be configurable
	traceeData->x11.screen.height = 1080;
	traceeData->x11.screen.mwidth = 1;
	traceeData->x11.screen.mheight = 1;
	traceeData->x11.screen.ndepths = 1;
	traceeData->x11.screen.depths = &(traceeData->x11.screenDepth);
	traceeData->x11.screen.root_depth = 8*3; // TODO: Look up correct value
	traceeData->x11.screen.root_visual = &(traceeData->x11.screenVisual);
	traceeData->x11.screen.white_pixel = 0xffffff;
	traceeData->x11.screen.black_pixel = 0;
	traceeData->x11.screen.max_maps = 0;
	traceeData->x11.screen.min_maps = 0;
	
	traceeData->x11.screenDepth.depth = 0; // TODO: Look up correct value for this
	traceeData->x11.screenDepth.nvisuals = 1;
	traceeData->x11.screenDepth.visuals = &(traceeData->x11.screenVisual);
	
	traceeData->x11.screenVisual.visualid = 102;
	traceeData->x11.screenVisual.class = 0; // TODO: Look up correct value for this
	traceeData->x11.screenVisual.bits_per_rgb = 8*3;
	traceeData->x11.screenVisual.map_entries = 0; // TODO: Look up correct value for this
	
	traceeData->x11.visualInfo.visual = &(traceeData->x11.screenVisual);
	traceeData->x11.visualInfo.visualid = 102;
	traceeData->x11.visualInfo.screen = 103;
}

EXPORT Display* XOpenDisplay(const char* name) {
	if((traceeData->x11.flags & LSS_X_DISPLAY_OPENED) != 0)
		fail("opening multiple displays is unsupported");
	
	initData();
	
	traceeData->x11.flags |= LSS_X_DISPLAY_OPENED;
	return &(traceeData->x11.display);
}

EXPORT int XCloseDisplay(Display* display) {
	traceeData->x11.flags &= ~LSS_X_DISPLAY_OPENED;
	return 0;
}

// Virtual window is always mapped
EXPORT int XMapWindow(Display* display, Window w) {
	return 0;
}
EXPORT int XUnmapWindow(Display* display, Window w) {
	return 0;
}

// Only supports RGBA, so ignore color map
EXPORT Colormap XCreateColormap(Display* display, Window window, Visual* visual, int alloc) {
	return 123;
}

EXPORT Window XCreateWindow(Display* display, Window window, int x, int y, unsigned int width, unsigned int height,
	unsigned int borderWidth, int depth, unsigned int class, Visual* visual, unsigned long valueMask, XSetWindowAttributes* attrs)
{
	if(display != &(traceeData->x11.display))
		fail("Unknown display passed to XCreateWindow");
	if((traceeData->x11.flags & LSS_X_WINDOW_OPENED) != 0)
		fail("Opening more than one window is unsupported");
	
	App2WrapperCmd cmd = CMD_OPENWINDOW;
	uint32_t w, h;
	w = width;
	h = height;
	writeData(TRACEE_WRITE_FD, &cmd, sizeof(cmd));
	writeData(TRACEE_WRITE_FD, &w, sizeof(w));
	writeData(TRACEE_WRITE_FD, &h, sizeof(h));
	
	traceeData->x11.flags |= LSS_X_WINDOW_OPENED;
	return LSS_X_APP_WINDOW;
}

EXPORT int XDestroyWindow(Display* display, Window window) {
	App2WrapperCmd cmd = CMD_CLOSEWINDOW;
	writeData(TRACEE_WRITE_FD, &cmd, sizeof(cmd));
	
	traceeData->x11.flags &= ~LSS_X_WINDOW_OPENED;
	return 0;
}

EXPORT int XSetNormalHints(Display* dislay, Window window, XSizeHints* hints) {
	return 0;
}

EXPORT int XSetStandardProperties(Display* display, Window window, const char* windowName, const char* iconName, Pixmap icon,
	char** argv, int argc, XSizeHints* hints)
{
	return 0;
}

EXPORT int XFree(void* ptr) {
	return 0;
}

EXPORT XVisualInfo* glXChooseVisual(Display* display, int screen, int* attrlist) {
	return &(traceeData->x11.visualInfo);
}

EXPORT GLXContext glXCreateContext(Display* display, XVisualInfo* visinfo, GLXContext shareList, Bool direct) {
	if((traceeData->x11.flags & LSS_X_CONTEXT_OPENED) != 0)
		fail("Creating more than one context is unsupported");
	
	traceeData->x11.flags |= LSS_X_CONTEXT_OPENED;
	
	// Return a dummy pointer
	return (GLXContext) 0x1;
}

EXPORT void glXDestroyContext(Display* display, GLXContext ctx) {
	traceeData->x11.flags &= ~LSS_X_CONTEXT_OPENED;
}

EXPORT Bool glXMakeCurrent(Display* display, GLXDrawable drawable, GLXContext ctx) {
	// Fake context is always current
	return 1;
}

EXPORT const char* glXQueryExtensionsString(Display* display, int screen) {
	// TODO: Implement
	return "";
}

EXPORT __GLXextFuncPtr glXGetProcAddressARB(const GLubyte* name) {
	return NULL;
}

EXPORT void glXSwapBuffers(Display* dpy, GLXDrawable drawable) {
	lss_pause();
}
