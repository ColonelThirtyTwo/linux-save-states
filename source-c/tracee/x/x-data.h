
#ifndef _LSS_X_DATA
#define _LSS_X_DATA

#include <stdint.h>

#define XLIB_ILLEGAL_ACCESS // Lets us access internals of X11 structs
#include <X11/Xlib.h>
#include <X11/Xutil.h>

// flags for lss_x_data.flags
#define LSS_X_DISPLAY_OPENED 0x1 // Set if the app has the display window open
#define LSS_X_WINDOW_OPENED  0x2 // Set if the app has the app window opened
#define LSS_X_CONTEXT_OPENED 0x4 // Set if the app has an OpenGL context created

#define LSS_X_ROOT_WINDOW 100
#define LSS_X_APP_WINDOW 101

typedef struct {
	uint32_t flags;
	
	Display display;
	Screen screen;
	Depth screenDepth;
	Visual screenVisual;
	XVisualInfo visualInfo;
} lss_x_data;

#endif
