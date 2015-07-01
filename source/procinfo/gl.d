/// Contains OpenGL state.
module procinfo.gl;

import std.stdio;
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
	
	void openWindow(uint width, uint height) {
		assert(!this.hasWindow);
		
		glfwWindowHint(GLFW_RESIZABLE, 0);
		glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_COMPAT_PROFILE);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);
		
		window = glfwCreateWindow(width, height, "TAS Window".toStringz, null, null);
		enforce(window != null, "Failed to create window.");
		
		glfwMakeContextCurrent(window);
		DerelictGL3.reload();
	}
	
	void closeWindow() {
		glfwDestroyWindow(window);
		window = null;
	}
	
	bool hasWindow() @property pure const nothrow @nogc {
		return window !is null;
	}
	
	void resizeWindow(uint width, uint height) {
		assert(this.hasWindow);
		glfwSetWindowSize(window, width, height);
	}
	
	void pollEvents() {
		glfwPollEvents();
	}
}
