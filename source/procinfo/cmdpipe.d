/// Pipe wrapper specialized for sending commands
module procinfo.cmdpipe;

import std.typetuple;
import std.traits;
import std.range;
import std.exception : enforce, assumeUnique;
import std.conv : to;
import std.typecons : Nullable;
import std.c.linux.linux;
import core.stdc.errno;

import procinfo.pipe;
import procinfo.commands;

/// Special file descriptors for the tracee.
/// Specifying a file descriptor here will cause LSS to ignore it when looking for open file descriptors to save.
enum SpecialFileDescriptors : int {
	/// Standard streams
	STDIN = 0,
	/// ditto
	STDOUT = 1,
	/// ditto
	STDERR = 2,
	
	/// FD that the tracee reads to get general commands
	TRACEE_READ_FD = 500,
	/// FD that the tracee writes to send general commands
	TRACEE_WRITE_FD = 501,
	
	/// FD that the tracee reads to get OpenGL data
	GL_READ_FD = 502,
	/// FD that the tracee writes to send OpenGL commands and data
	GL_WRITE_FD = 503,
}

private template ValueOfEnum(SpecialFileDescriptors v) {
	enum int ValueOfEnum = cast(int) v;
}

/// Range of special file descriptors. Contains the values of `SpecialFileDescriptors`
enum AllSpecialFileDescriptors = only(staticMap!(ValueOfEnum, EnumMembers!SpecialFileDescriptors));

private alias linux_write = write;
private alias linux_read = read;

/// Command pipe used for communicating with the traced process.
struct CommandPipe {
	Pipe pipe;
	alias pipe this;
	
	/// Creates a command pipe.
	static CommandPipe create() {
		CommandPipe cmdpipe;
		cmdpipe.pipe = Pipe(true);
		
		return cmdpipe;
	}
	
	/// Writes some data to the command stream.
	void write(T)(T v)
	if(staticIndexOf!(Unqual!T, int, uint, long, ulong) != -1) {
		this.pipe.write((&v)[0..1]);
	}
	
	/// ditto
	void write(T)(T v)
	if(isSomeString!T) {
		string s = to!string(v);
		assert(s.length <= uint.max);
		this.write(cast(uint) s.length);
		
		this.pipe.write(s);
	}
	
	/// ditto
	void write(T)(T v)
	if(is(T : const(void)*)) {
		this.write(cast(size_t)v);
	}
	
	/// ditto
	void write(T)(T v)
	if(is(T : Wrapper2AppCmd)) {
		this.write(cast(int)v);
	}
	
	private void rawRead(scope void[] buf) {
		while(buf.length > 0) {
			void[] amntRead = buf;
			this.pipe.read(amntRead);
			buf = buf[amntRead.length..$];
		}
	}
	
	/// Reads some data from the command pipe.
	T read(T)()
	if(staticIndexOf!(T, int, uint, long, ulong) != -1) {
		T v;
		rawRead((&v)[0..1]);
		return v;
	}
	
	/// ditto
	T read(T)()
	if(is(T == string)) {
		auto len = this.read!uint();
		auto buf = new char[len];
		rawRead(buf);
		return assumeUnique(buf);
	}
	
	/// ditto
	T read(T)()
	if(is(T : void*)) {
		return cast(void*) this.read!size_t();
	}
	
	/// ditto
	T read(T)()
	if(is(T : App2WrapperCmd)) {
		return cast(App2WrapperCmd) this.read!int();
	}
	
	/// Similar to read!App2WrapperCmd, but does not block and returns null if no command was received.
	Nullable!App2WrapperCmd peekCommand() {
		this.pipe.blocking = false;
		scope(exit) this.pipe.blocking = true;
		
		int cmdInt;
		void[] buf = (&cmdInt)[0..1];
		try {
			this.pipe.read(buf);
		} catch(PipeClosedException) {
			return Nullable!App2WrapperCmd();
		}
		
		if(buf.ptr is null)
			return Nullable!App2WrapperCmd();
		enforce(buf.length == int.sizeof, "Read only part of a command before running out of data");
		return Nullable!App2WrapperCmd(cast(App2WrapperCmd)cmdInt);
	}
}
