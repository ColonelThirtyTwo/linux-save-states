
#ifndef _LSS_X_DATA
#define _LSS_X_DATA

#include <stdint.h>

#define XLIB_ILLEGAL_ACCESS // Lets us access internals of X11 structs
#include <X11/Xlib.h>

// flags for lss_x_data.flags
#define LSS_X_DISPLAY_OPENED 0x1 // Set if the app has the display window open
#define LSS_X_WINDOW_OPENED  0x2 // Set if the app has the app window opened
#define LSS_X_WINDOW_MAPPED  0x4 // Set if the app has the app window mapped

typedef struct {
	uint32_t flags;
	
	Display display;
	Window rootWindow;
	Window appWindow;
	Screen screen;
} lss_x_data;

#endif
