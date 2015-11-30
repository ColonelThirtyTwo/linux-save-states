/// Contains OpenGL state.
module procinfo.gl;

import std.stdio;
import std.typecons;
import std.exception : enforce, assumeWontThrow;
import std.string : toStringz, fromStringz;
import core.stdc.config;

import derelict.glfw3.glfw3;
import derelict.opengl3.gl;

private {
	extern(C) {
		void errorCallback(int error, const(char)* description) nothrow {
			assumeWontThrow(stderr.writeln("GLFW error: ", description.fromStringz));
		}
		
		void cursorCallback(GLFWwindow* window, double x, double y) nothrow {
			assumeWontThrow(stderr.writeln("cursor pos: ", x, ", ", y));
		}
		
		// Copied+adapted from xlib. Need the struct to access the `fd` field, so that
		// we can wait on window events as well as file and signals in libevent.
		struct XDisplay {
			void*ext_data;	/* hook for extension to hang data */
			void *private1;
			int fd;			/* Network socket. */
			int private2;
			int proto_major_version;/* major version of server's X protocol */
			int proto_minor_version;/* minor version of servers X protocol */
			char *vendor;		/* vendor of the server hardware */
			c_ulong private3;
			c_ulong private4;
			c_ulong private5;
			int private6;
			void function() resource_alloc;
			int byte_order;		/* screen byte order, LSBFirst, MSBFirst */
			int bitmap_unit;	/* padding and data requirements */
			int bitmap_pad;		/* padding requirements on bitmaps */
			int bitmap_bit_order;	/* LeastSignificant or MostSignificant */
			int nformats;		/* number of pixmap formats in list */
			void *pixmap_format;	/* pixmap format list */
			int private8;
			int release;		/* release of the server */
			void* private9;
			void* private10;
			int qlen;		/* Length of input event queue */
			c_ulong last_request_read; /* seq number of last event read */
			c_ulong request;	/* sequence number of last request. */
			void* private11;
			void* private12;
			void* private13;
			void* private14;
			uint max_request_size; /* maximum number 32 bit words in request*/
			void *db;
			void function() private15;
			char *display_name;	/* "host:display" string used on this connect*/
			int default_screen;	/* default screen for operations */
			int nscreens;		/* number of screens on this server*/
			void *screens;	/* pointer to list of screens */
			c_ulong motion_buffer;	/* size of motion buffer */
			c_ulong private16;
			int min_keycode;	/* minimum defined keycode */
			int max_keycode;	/* maximum defined keycode */
			void* private17;
			void* private18;
			int private19;
			char *xdefaults;	/* contents of defaults from server */
			/* there is more to this structure, but it is private to Xlib */
		}
		
		static assert(XDisplay.sizeof == 296); // Check that the XDisplay definition is correct. size measured from a test C program.
		
		alias glfwGetX11Display_t = XDisplay* function();
	}
	
	__gshared glfwGetX11Display_t glfwGetX11Display;
	
	// Replace derelict's GLFW loader with one that also loads the internal `glfwGetX11Display` function
	class InternalGLFW3Loader : DerelictGLFW3Loader {
		protected override void loadSymbols() {
			super.loadSymbols();
			bindFunc(cast(void**) &glfwGetX11Display, "glfwGetX11Display");
		}
	}
	
	static this() {
		DerelictGLFW3 = new InternalGLFW3Loader();
	}
}

/// Initializes GLFW. Call once at startup.
void initGl() {
	DerelictGL3.load();
	DerelictGLFW3.load();
	
	glfwSetErrorCallback(&errorCallback);
	enforce(glfwInit() != 0, "Failed to initialize GLFW.");
}

/// Returns the file descriptor used by X11.
/// For use with `select`, `poll`, etc. only.
/// Requires `initGl` to have been called.
int x11EventsFd() @property {
	return glfwGetX11Display().fd;
}

/++
 + Manages the OpenGL context and window.
++/
final class GlWindow {
	private GLFWwindow* window;
	
	/// Opens a window with the specified dimensions.
	/// A window must not already have been opened.
	void open(uint width, uint height) {
		assert(!this.isOpen);
		
		glfwWindowHint(GLFW_RESIZABLE, 0);
		/*glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_COMPAT_PROFILE);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);*/
		
		window = glfwCreateWindow(width, height, "TAS Window".toStringz, null, null);
		enforce(window != null, "Failed to create window.");
		
		glfwMakeContextCurrent(window);
		DerelictGL3.reload();
		
		//enforce(glfwExtensionSupported("EXT_direct_state_access".toStringz), "EXT_direct_state_access unsupported by this GPU.");
		
		glfwSetCursorPosCallback(window, &cursorCallback);
	}
	/// ditto
	void open(Tuple!(uint, uint) size) {
		this.open(size[0], size[1]);
	}
	
	/// Closes a window.
	/// A window must be opened.
	void close() {
		assert(this.isOpen);
		glfwDestroyWindow(window);
		window = null;
	}
	
	/// Returns true if a window is opened
	bool isOpen() @property pure const nothrow @nogc {
		return window !is null;
	}
	
	/// Resizes the window.
	/// A window must be opened.
	void resize(uint width, uint height) {
		assert(this.isOpen);
		glfwSetWindowSize(window, width, height);
	}
	
	/// ditto
	void resize(Tuple!(uint, uint) size) {
		this.resize(size[0], size[1]);
	}
	
	/// Returns the window size in pixels.
	/// A window must be opened.
	Tuple!(uint,uint) size() @property nothrow @nogc {
		assert(this.isOpen);
		int w,h;
		glfwGetFramebufferSize(window, &w, &h);
		return Tuple!(uint, uint)(w,h);
	}
	
	/// Polls input events using glfwPollEvents
	void pollEvents() {
		glfwPollEvents();
	}
}
