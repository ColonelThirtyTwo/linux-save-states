/// Command Pipe
module procinfo.cmdpipe;

import std.typetuple;
import std.traits;
import std.range;
import std.exception : enforce, errnoEnforce, assumeUnique;
import std.conv : to, octal;
import std.format : format;
import std.typecons : Nullable;
import std.c.linux.linux;
import core.stdc.errno;

import procinfo.commands;

/// Thrown by read functions if the pipe was closed before or during a read.
final class PipeClosedException : Exception {
	this(string file=__FILE__, size_t line=__LINE__) {
		super("Pipe closed");
	}
}

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

enum AllSpecialFileDescriptors = only(staticMap!(ValueOfEnum, EnumMembers!SpecialFileDescriptors));

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
	private int tracerReaderFd, tracerWriterFd;
	private int traceeReaderFd, traceeWriterFd;
	
	/// Creates a command pipe.
	static CommandPipe create() {
		CommandPipe cmdpipe;
		
		// Create pipes
		int[2] tracer2traceePipe;
		int[2] tracee2tracerPipe;
		
		errnoEnforce(pipe2(tracer2traceePipe.ptr, O_CLOEXEC) != -1);
		errnoEnforce(pipe2(tracee2tracerPipe.ptr, O_CLOEXEC) != -1);
		
		cmdpipe.tracerReaderFd = tracee2tracerPipe[0];
		cmdpipe.tracerWriterFd = tracer2traceePipe[1];
		
		cmdpipe.traceeReaderFd = tracer2traceePipe[0];
		cmdpipe.traceeWriterFd = tracee2tracerPipe[1];
		
		return cmdpipe;
	}
	
	/// Clones the tracee's pipe endpoins to the hardcoded locations that the tracee expects.
	/// This should be called in the forked process, before calling exec.
	void setupTraceePipes(int readfd, int writefd)
	in {
		assert(traceeReaderFd != 0, "Tracee pipe was closed");
		assert(traceeWriterFd != 0, "Tracee pipe was closed");
	} body {
		errnoEnforce(dup2(traceeReaderFd, readfd) != -1);
		errnoEnforce(dup2(traceeWriterFd, writefd) != -1);
	}
	
	/// Closes the tracers copy of the tracee's command pipes. This should be called
	/// by the parent process after fork.
	void closeTraceePipes()
	in {
		assert(traceeReaderFd != 0, "Tracee pipe was closed");
		assert(traceeWriterFd != 0, "Tracee pipe was closed");
	} body {
		errnoEnforce(close(traceeReaderFd) != -1);
		errnoEnforce(close(traceeWriterFd) != -1);
		traceeReaderFd = 0;
		traceeWriterFd = 0;
	}
	
	/// Returns the file descriptor of the pipe used to read commands from the tracee.
	/// This should only be used with `select`, et.al. to check for pending data.
	int readFD() @property const pure nothrow @nogc {
		return tracerReaderFd;
	}
	
	private void rawWrite(const(void)[] buf) {
		while(buf.length > 0) {
			ssize_t numWritten = linux_write(tracerWriterFd, buf.ptr, buf.length);
			errnoEnforce(numWritten != -1);
			buf = buf[numWritten..$];
		}
	}
	
	/// Writes some data to the command stream.
	void write(T)(T v)
	if(staticIndexOf!(Unqual!T, int, uint, long, ulong) != -1) {
		rawWrite((&v)[0..1]);
	}
	
	/// ditto
	void write(T)(T v)
	if(isSomeString!T) {
		string s = to!string(v);
		assert(s.length <= uint.max);
		this.write(cast(uint) s.length);
		
		rawWrite(s);
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
			auto numRead = linux_read(tracerReaderFd, buf.ptr, buf.length);
			errnoEnforce(numRead != -1);
			if(numRead == 0)
				throw new PipeClosedException;
			buf = buf[numRead..$];
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
		errnoEnforce(fcntl(tracerReaderFd, F_SETFL, O_NONBLOCK) != -1);
		scope(exit) errnoEnforce(fcntl(tracerReaderFd, F_SETFL, 0) != -1);
		
		int cmdInt;
		void[] buf = (&cmdInt)[0..1];
		
		while(buf.length > 0) {
			auto numRead = linux_read(tracerReaderFd, buf.ptr, buf.length);
			if(numRead == 0)
				return Nullable!App2WrapperCmd();
			if(numRead == -1 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
				enforce(buf.length == int.sizeof, "Read only part of a command before running out of data");
				return Nullable!App2WrapperCmd();
			}
			errnoEnforce(numRead != -1);
			buf = buf[numRead..$];
		}
		return Nullable!App2WrapperCmd(cast(App2WrapperCmd)cmdInt);
	}
}
