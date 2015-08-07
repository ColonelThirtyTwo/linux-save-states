
module opengl.gldispatch;

import std.typetuple;
import std.algorithm;
import std.array;
import std.typecons;
import std.traits;
import std.format;
import std.conv;
import core.thread;

import procinfo.pipe;

import derelict.opengl3.types;
import gl = derelict.opengl3.gl;

private {
	template Arr2Tuple(alias Arr) {
		static if(Arr.length == 0)
			alias Arr2Tuple = TypeTuple!();
		else static if(Arr.length == 1)
			alias Arr2Tuple = TypeTuple!(Arr[0]);
		else
			alias Arr2Tuple = TypeTuple!(Arr2Tuple!(Arr[0..$/2]), Arr2Tuple!(Arr[$/2..$]));
	}
	
	struct FuncInfoT {
		string name;
		string type;
		int id;
	}
	
	enum Funcs = import("gl-list.csv")
		.splitter("\n")
		.map!(row => row.split(","))
		.filter!(row => row.length == 3)
		.map!(row => FuncInfoT(row[0], row[1], row[2].to!int))
		.array
	;
	
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
	
	template PtrToArray(T) {
		static if(is(T U : U*))
			alias PtrToArray = U[];
		else
			static assert(false);
	}
}

final class GlDispatch {
	
	this(Pipe pipe) {
		this.pipe = pipe;
		this.fiber = new Fiber(&this.main);
	}
	
	void poll() {
		if(this.fiber.state != Fiber.State.TERM)
			this.fiber.call();
	}
	
private:
	Pipe pipe;
	Fiber fiber;
	
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
		mixin(Funcs.map!(info => `case %d: return this.handle!"%s"();`.format(info.id, info.name)).join("\n"));
		case 9001:
			// glFlush called
			glFlush();
			return;
		}
	}
	
	T read(T)()
	if(!is(T U : U*)) {
		T obj;
		void[] buf = (&obj)[0..1];
		while(buf.length != 0) {
			auto partRead = buf;
			this.pipe.read(partRead);
			if(partRead.ptr is null)
				// Yield until we have more.
				Fiber.yield();
			else
				buf = buf[partRead.length..$];
		}
		return obj;
	}
	
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
	
	void write(T)(T val)
	if(!hasIndirections!T) {
		void[] buf = (&val)[0..1];
		this.pipe.write(buf);
	}
	
	void write(T)(T val)
	if(is(T U : U[]) && !hasIndirections!U) {
		this.pipe.write(val);
	}
	
	void handle(string funcname)() {
		enum Info = FuncInfo[funcname];
		
		
		static if(Info.type == "alias" || Info.type == "placeholder")
			assert(false, "Received  for a "~Info.type~" function");
		else static if(Info.type == "basic")
			return handle_basic!(funcname)();
		else static if(Info.type == "gen")
			return handle_gen!(funcname)();
		else
			static assert(false, "Unrecognized GL function type: "~Info.type);
	}
	
	void handle_basic(string funcname)() {
		auto glFunc = __traits(getMember, gl, funcname);
		alias ParamTypes = staticMap!(Unqual, ParameterTypeTuple!(typeof(glFunc)));
		alias ParamStructTypes = staticMap!(ReplaceBufferWithSize, ParamTypes);
		
		struct ReceivedParams {
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
		auto glFunc = __traits(getMember, gl, funcname);
		alias ParamTypes = staticMap!(Unqual, ParameterTypeTuple!(typeof(glFunc)));
		static assert(is(ParamTypes[0] == GLsizei));
		static assert(is(ParamTypes[1] == GLuint*));
		
		auto bufs = new GLuint[read!GLsizei];
		glFunc(cast(GLsizei)bufs.length, bufs.ptr);
		write(bufs);
	}
}
