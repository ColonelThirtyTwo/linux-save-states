
#include "tracee.h"
#include "x/x.h"

#define XLIB_ILLEGAL_ACCESS // Lets us access internals of X11 structs
#include <X11/Xlib.h>

#include <stddef.h>
#include <dlfcn.h>

/*EXPORT Display* XOpenDisplay(const char* name) {
	
}*/

EXPORT void glXSwapBuffers(void* dpy, XID drawable) {
	static void(*oldglXSwapBuffers)(void*,XID) = NULL;
	
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
