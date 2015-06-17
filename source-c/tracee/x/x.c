
#include "tracee.h"
#include "x/x.h"

#include <stddef.h>
#include <X11/X.h>
#include <dlfcn.h>

__attribute__((visibility("default"))) void glXSwapBuffers(void* dpy, XID drawable) {
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
