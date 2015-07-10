/// Contains OpenGL state.
module procinfo.gl;

import std.stdio;
import std.typecons;
import std.exception : enforce, assumeWontThrow;
import std.string : toStringz, fromStringz;

import derelict.glfw3.glfw3;
import derelict.opengl3.gl;

private extern(C) nothrow errorCallback(int error, const(char)* description) {
	assumeWontThrow(stderr.writeln("GLFW error: ", description.fromStringz));
}

/// Contains the OpenGL state.
struct OpenGLState {
	private GLFWwindow* window;
	
	static void init() {
		DerelictGL3.load();
		DerelictGLFW3.load();
		
		glfwSetErrorCallback(&errorCallback);
		enforce(glfwInit() != 0, "Failed to initialize GLFW.");
	}
	
	/// Opens a window with the specified dimensions.
	/// A window must not already have been opened.
	void openWindow(uint width, uint height) {
		assert(!this.hasWindow);
		
		glfwWindowHint(GLFW_RESIZABLE, 0);
		/*glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_COMPAT_PROFILE);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);*/
		
		window = glfwCreateWindow(width, height, "TAS Window".toStringz, null, null);
		enforce(window != null, "Failed to create window.");
		
		glfwMakeContextCurrent(window);
		DerelictGL3.reload();
	}
	/// ditto
	void openWindow(Tuple!(uint, uint) size) {
		this.openWindow(size[0], size[1]);
	}
	
	/// Closes a window.
	/// A window must be opened.
	void closeWindow() {
		assert(this.hasWindow);
		glfwDestroyWindow(window);
		window = null;
	}
	
	/// Returns true if a window is opened
	bool hasWindow() @property pure const nothrow @nogc {
		return window !is null;
	}
	
	/// Resizes the window.
	/// A window must be opened.
	void resizeWindow(uint width, uint height) {
		assert(this.hasWindow);
		glfwSetWindowSize(window, width, height);
	}
	
	/// ditto
	void resizeWindow(Tuple!(uint, uint) size) {
		this.resizeWindow(size[0], size[1]);
	}
	
	/// Returns the window size in pixels.
	/// A window must be opened.
	Tuple!(uint,uint) windowSize() @property nothrow @nogc {
		assert(this.hasWindow);
		int w,h;
		glfwGetFramebufferSize(window, &w, &h);
		return Tuple!(uint, uint)(w,h);
	}
	
	/// Polls input events using glfwPollEvents
	void pollEvents() {
		glfwPollEvents();
	}
}
