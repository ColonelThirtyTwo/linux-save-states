
#include "tracee.h"
#include "x/x.h"

#define XLIB_ILLEGAL_ACCESS // Lets us access internals of X11 structs
#include <X11/Xlib.h>

#include <stddef.h>
#include <dlfcn.h>

/*
static void initData() {
	#define FILL_ZERO(x) __builtin_memset(&(x), 0, sizeof(x))
	FILL_ZERO(traceeData->x11.display);
	FILL_ZERO(traceeData->x11.screen);
	FILL_ZERO(traceeData->x11.appWindow);
	FILL_ZERO(traceeData->x11.rootWindow);
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
	
	traceeData->x11.screen.root = &(traceeData->x11.rootWindow);
	//traceeData->x11.screen.
}

EXPORT Display* XOpenDisplay(const char* name) {
	if((traceeData->x11.flags & LSS_X_DISPLAY_OPENED) != 0)
		fail("display already open");
	
	initData();
	
	traceeData->x11.flags |= LSS_X_DISPLAY_OPENED;
	return &(traceeData->x11.display);
}*/

EXPORT void glXSwapBuffers(void* dpy, XID drawable) {
	static void(*oldglXSwapBuffers)(void*,XID) = NULL; // TODO: should be put in traceeData
	
	if(oldglXSwapBuffers == NULL) {
		void* handle = dlopen("libGL.so", RTLD_LAZY);
		if(handle == NULL)
			fail(dlerror());
		oldglXSwapBuffers = dlsym(handle, "glXSwapBuffers");
		if(oldglXSwapBuffers == NULL)
			fail(dlerror());
	}
	
	lss_pause();
	oldglXSwapBuffers(dpy, drawable);
}
