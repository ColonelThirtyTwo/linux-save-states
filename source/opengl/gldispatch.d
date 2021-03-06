
/// Dispatches OpenGL commands
module opengl.gldispatch;

import std.typetuple;
import std.algorithm;
import std.array;
import std.typecons;
import std.traits;
import std.format;
import std.conv;
import std.experimental.logger;
import core.thread;

import derelict.opengl3.types;
import gl = derelict.opengl3.gl;

import procinfo.pipe;
import opengl.idmaps;

private {
	struct FuncInfoT {
		string name;
		string type;
		int id;
	}
	
	version(SkipOpenGLDispatch) {
		// With the SkipOpenGLDispatch version, the receivers for the tracee OpenGL commands
		// are not read or implemented. This speeds up compilation in exchange for a build that
		// does not implement OpenGL. Used mostly for testing.
		enum FuncInfoT[] Funcs = [];
	} else {
		enum Funcs = import("gl-list.csv")
			.splitter("\n")
			.map!(row => row.split(","))
			.filter!(row => row.length == 3)
			.map!(row => FuncInfoT(row[0], row[1], row[2].to!int))
			.array
		;
	}
	
	enum FuncInfo = Funcs.map!(info => tuple(info.name, info)).assocArray;
	
	template IsBuffer(T) {
		enum IsBuffer = isPointer!T;
	}
	
	template ReplaceBufferWithSize(T) {
		static if(IsBuffer!T)
			alias ReplaceBufferWithSize = size_t;
		else
			alias ReplaceBufferWithSize = T;
	}
}

/++
 + Reads and dispatches OpenGL commands from a pipe.
 +
 + To simplify the tracer design and improve performance, GL commands are processed separately from the
 + regular commands. A list of all OpenGL functions is generated by the `gen-gl-wrappers.py` function as a CSV
 + file in `resources/gl=list.csv`. That list is parsed at compile-time to generate handlers for each
 + OpenGL function.
 + 
 + Command parsing is done in a fiber, so that the full data for the command need not be completely available
 + before returning.
++/
final class GlDispatch {
	///
	this(Pipe pipe, IdMaps idmaps) {
		this.pipe = pipe;
		this.fiber = new Fiber(&this.main);
		this.idmaps = idmaps;
	}
	
	/++
	 + Polls the command pipe, reading and executing commands until the pipe is drained.
	++/
	void poll() {
		if(this.fiber.state != Fiber.State.TERM)
			this.fiber.call();
	}
	
private:
	Pipe pipe;
	Fiber fiber;
	IdMaps idmaps;
	
	void main() {
		while(true) {
			int cmd;
			try {
				cmd = read!int;
			} catch(PipeClosedException) {
				return;
			}
			oneCommand(cmd);
		}
	}
	
	void oneCommand(int cmd) {
		final switch(cmd) {
		mixin(Funcs.map!(info => `case %d:
			static if(__traits(hasMember, this, "handle_func_%s"))
				return this.handle_func_%s();
			else
				return this.handle!"%s"();
		`.format(info.id, info.name, info.name, info.name)).join("\n"));
		}
	}
	
	/// Reads a fixed-sized type from the pipe
	T read(T)()
	if(!is(T U : U*)) {
		T obj;
		void[] buf = (&obj)[0..1];
		while(buf.length != 0) {
			auto partRead = buf;
			this.pipe.read(partRead);
			if(partRead.ptr is null)
				// Yield until we have more data to read.
				Fiber.yield();
			else
				buf = buf[partRead.length..$];
		}
		return obj;
	}
	
	/// Reads a variable-length type from the pipe.
	T read(T)(size_t size)
	if(is(T U : U*)) {
		auto buf = new void[size];
		T ptr = cast(T) buf.ptr;
		
		while(buf.length != 0) {
			auto partRead = buf;
			this.pipe.read(partRead);
			if(partRead.ptr is null)
				Fiber.yield();
			else
				buf = buf[partRead.length..$];
		}
		
		return ptr;
	}
	
	/// Writes a value type
	void write(T)(T val)
	if(!hasIndirections!T) {
		void[] buf = (&val)[0..1];
		this.pipe.write(buf);
	}
	
	/// Writes an array
	void write(T)(T val)
	if(is(T U : U[]) && !hasIndirections!U) {
		this.pipe.write(val);
	}
	
	void handle(string funcname)() {
		enum Info = FuncInfo[funcname];
		
		static if(Info.type == "alias" || Info.type == "placeholder")
			assert(false, "Received command for function "~funcname~" (a "~Info.type~" function)");
		else static if(!is(typeof(__traits(getMember, gl, funcname)))) {
			pragma(msg, "Warning: derelict does not expose function "~funcname~"; will not generate handler.");
			assert(false, "Received command for function "~funcname~" (handler was omitted during build)");
		} else static if(Info.type == "basic")
			return handle_basic!(funcname)();
		else static if(Info.type == "gen")
			return handle_gen!(funcname)();
		else static if(Info.type == "delete")
			return handle_delete!(funcname)();
		else static if(Info.type == "special")
			return __traits(getMember, this, "handle_func_"~funcname)();
		else
			static assert(false, "Unrecognized GL function type: "~Info.type);
	}
	
	void handle_basic(string funcname)() {
		// Basic OpenGL functions
		auto glFunc = __traits(getMember, gl, funcname);
		alias ParamTypes = staticMap!(Unqual, ParameterTypeTuple!(typeof(glFunc)));
		alias ParamStructTypes = staticMap!(ReplaceBufferWithSize, ParamTypes);
		
		static align(1) struct ReceivedParams {
			align(1):
			ParamStructTypes params;
		}
		auto receivedParams = read!ReceivedParams();
		
		ParamTypes params;
		
		foreach(i, T; ParamTypes) {
			static if(IsBuffer!T)
				params[i] = read!T(receivedParams.params[i]);
			else
				params[i] = receivedParams.params[i];
		}
		
		static if(is(ReturnType!(typeof(glFunc)) == void))
			glFunc(params);
		else {
			auto result = glFunc(params);
			write(result);
		}
	}
	
	void handle_gen(string funcname)() {
		// glGen* functions
		auto glFunc = __traits(getMember, gl, funcname);
		alias ParamTypes = staticMap!(Unqual, ParameterTypeTuple!(typeof(glFunc)));
		static assert(is(ParamTypes[0] == GLsizei));
		static assert(is(ParamTypes[1] == GLuint*));
		
		static if(funcname == "glGenBuffers") {
			auto ids = idmaps.newBuffers(read!GLsizei);
		} else {
			auto ids = new GLuint[read!GLsizei];
			glFunc(cast(GLsizei)ids.length, ids.ptr);
		}
		write(ids);
	}
	
	void handle_delete(string funcname)() {
		// glDelete* functions
		auto glFunc = __traits(getMember, gl, funcname);
		alias ParamTypes = staticMap!(Unqual, ParameterTypeTuple!(typeof(glFunc)));
		static assert(is(ParamTypes[0] == GLsizei));
		static assert(is(ParamTypes[1] == const(GLuint)*));
		
		auto count = read!GLsizei;
		auto ids = read!(GLuint*)(read!size_t)[0..count];
		
		static if(funcname == "glDeleteBuffers") {
			idmaps.deleteBuffers(ids);
		} else {
			glFunc(cast(int) ids.length, ids.ptr);
		}
	}
	
	void handle_func_glFlush() {
		gl.glFlush();
	}
	
	void handle_func_glGetBufferSubData() {
		static align(1) struct Params {
			align(1):
			GLenum target;
			GLintptr offset;
			GLsizeiptr size;
		}
		auto args = read!Params();
		
		auto buf = new ubyte[args.size];
		gl.glGetBufferSubData(args.target, args.offset, args.size, buf.ptr);
		write(buf);
	}
	
	void handle_func_glGetBufferParameteriv() {
		static align(1) struct Params {
			align(1):
			GLenum target;
			GLenum param;
		}
		auto args = read!Params();
		
		GLint rv;
		gl.glGetBufferParameteriv(args.target, args.param, &rv);
		write(rv);
	}
}
