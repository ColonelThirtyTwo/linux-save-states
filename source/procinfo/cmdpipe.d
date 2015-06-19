/// Command Pipe
module procinfo.cmdpipe;

import std.typetuple : staticIndexOf;
import std.traits : Unqual, isSomeString;
import std.exception : enforce, errnoEnforce, assumeUnique;
import std.conv : to, octal;
import std.format : format;
import std.c.linux.linux;

/// Commands passed from the wrapper proc to the traced proc. See `resources/wrapper2appcmds`.
mixin(q{
	enum Wrapper2AppCmd {
		%s
	};
}.format(import("wrapper2appcmds")));

/// Commands passed from the traced proc to the wrapper proc. See `resources/app2wrappercmds`.
mixin(q{
	enum App2WrapperCmd {
		%s
	};
}.format(import("app2wrappercmds")));

/// The file descriptor that the traced app reads to get commands.
enum APP_READ_FD = 500;
/// The file descriptor that the traced app write to send commands.
enum APP_WRITE_FD = 501;

private extern(C) @nogc nothrow {
	int pipe2(int* pipefd, int flags);
	enum O_CLOEXEC = octal!2000000;
}

private alias linux_write = write;
private alias linux_read = read;

/// Command pipe used for communicating with the traced process.
/// This uses Linux pipes (see pipe(7) and pipe(2)) for communication.
/// When the process forks to create the tracee, it calls `setupPipes` to place the pipes at a fixed FD (given by `APP_READ_FD` and `APP_WRITE_FD`).
struct CommandPipe {
	private int wrapperReaderFd, wrapperWriterFd;
	private int appReaderFd, appWriterFd;
	
	/// Creates a command pipe.
	static CommandPipe create() {
		CommandPipe cmdpipe;
		
		// Create pipes
		int[2] wrapper2appPipe;
		int[2] app2wrapperPipe;
		
		errnoEnforce(pipe2(wrapper2appPipe.ptr, O_CLOEXEC) != -1);
		errnoEnforce(pipe2(app2wrapperPipe.ptr, O_CLOEXEC) != -1);
		
		cmdpipe.wrapperReaderFd = app2wrapperPipe[0];
		cmdpipe.wrapperWriterFd = wrapper2appPipe[1];
		
		cmdpipe.appReaderFd = wrapper2appPipe[0];
		cmdpipe.appWriterFd = app2wrapperPipe[1];
		
		return cmdpipe;
	}
	
	/// Clones the tracee's pipe endpoins to the hardcoded locations that the tracee expects.
	/// This should be called in the forked process, before calling exec.
	void setupTraceePipes() {
		errnoEnforce(dup2(appReaderFd, APP_READ_FD) != -1);
		errnoEnforce(dup2(appWriterFd, APP_WRITE_FD) != -1);
	}
	
	/// Closes the tracers copy of the tracee's command pipes. This should be called
	/// by the parent process after fork.
	void closeTraceePipes() {
		errnoEnforce(close(appReaderFd) != -1);
		errnoEnforce(close(appWriterFd) != -1);
	}
	
	/// Writes some data to the command stream.
	void write(T)(T v)
	if(staticIndexOf!(Unqual!T, int, uint, long, ulong) != -1) {
		ssize_t written = linux_write(wrapperWriterFd, &v, T.sizeof);
		errnoEnforce(written != -1);
		enforce(written == T.sizeof, "Didn't write enough data.");
	}
	
	/// ditto
	void write(T)(T v)
	if(isSomeString!T) {
		string s = to!string(v);
		assert(s.length <= uint.max);
		this.write(cast(uint) s.length);
		
		ssize_t written = linux_write(wrapperWriterFd, s.ptr, s.length);
		errnoEnforce(written != -1);
		enforce(written == s.length, "Didn't write enough data.");
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
	
	/// Reads some data from the command pipe.
	T read(T)()
	if(staticIndexOf!(T, int, uint, long, ulong) != -1) {
		T v;
		
		ssize_t numRead = linux_read(wrapperReaderFd, &v, T.sizeof);
		errnoEnforce(numRead != -1);
		enforce(numRead == T.sizeof, "Didn't read enough data.");
		return v;
	}
	
	/// ditto
	T read(T)()
	if(is(T == string)) {
		auto len = this.read!uint();
		auto buf = new char[len];
		
		ssize_t numRead = linux_read(wrapperReaderFd, buf.ptr, buf.length);
		errnoEnforce(numRead != -1);
		enforce(numRead == buf.length, "Didn't read enough data.");
		
		return assumeUnique(buf);
	}
	
	/// ditto
	T read(T)()
	if(is(T : void*)) {
		return cast(void*) this.read!size_t();
	}
	
	/// ditto
	T read(T)()
	if(is(T : Wrapper2AppCmd)) {
		return cast(Wrapper2AppCmd) this.read!int();
	}
}
