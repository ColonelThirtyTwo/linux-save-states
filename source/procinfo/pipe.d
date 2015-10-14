module procinfo.pipe;

import std.exception;
import std.conv : octal;
import std.c.linux.linux;
import core.stdc.errno;

/// Thrown by read functions if the pipe was closed before or during a read.
final class PipeClosedException : Exception {
	this(string file=__FILE__, size_t line=__LINE__) {
		super("Pipe closed");
	}
}


private extern(C) @nogc nothrow {
	int pipe2(int* pipefd, int flags);
	enum O_CLOEXEC = octal!2000000;
}

/++
 + Bidirectional communication between the tracer and tracee.
 +
 + This uses Linux pipes for communication.
++/
struct Pipe {
	private int tracerReaderFd, tracerWriterFd;
	private int traceeReaderFd, traceeWriterFd;
	
	/// Creates a new pipe.
	/// If blocking is false, sets the tracer read pipe to non-blocking mode.
	this(bool blocking) {
		// Create pipes
		int[2] tracer2traceePipe;
		int[2] tracee2tracerPipe;
		
		errnoEnforce(pipe2(tracer2traceePipe.ptr, O_CLOEXEC) != -1);
		errnoEnforce(pipe2(tracee2tracerPipe.ptr, O_CLOEXEC) != -1);
		
		this.tracerReaderFd = tracee2tracerPipe[0];
		this.tracerWriterFd = tracer2traceePipe[1];
		
		this.traceeReaderFd = tracer2traceePipe[0];
		this.traceeWriterFd = tracee2tracerPipe[1];
		
		if(!blocking)
			fcntl(tracerReaderFd, F_SETFL, O_NONBLOCK);
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
	
	/// Sets the blocking mode of the pipe
	void blocking(bool block) @property {
		errnoEnforce(fcntl(tracerReaderFd, F_SETFL, block ? 0 : O_NONBLOCK) != -1);
	}
	
	/// Returns the file descriptor of the pipe used to read commands from the tracee.
	/// This should only be used with `select`, et.al. to check for pending data.
	int readFD() @property const pure nothrow @nogc {
		return tracerReaderFd;
	}
	
	/**
	 * Reads from the pipe.
	 *
	 * This should be passed a buffer to fill, with a length equal to the amount of
	 * bytes to read. Data is read directly into the buffer, and the buffer's length
	 * is altered to the amount of data read.
	 *
	 * If the pipe is closed, throws PipeClosedException.
	 * If the pipe was opened in non-blocking mode and there is no data to read currently,
	 * the buffer is set to null.
	**/
	void read(ref void[] buf) {
		auto readAmount = .read(tracerReaderFd, buf.ptr, buf.length);
		if(readAmount == 0)
			throw new PipeClosedException();
		if(readAmount == -1) {
			if(errno == EAGAIN || errno == EWOULDBLOCK) {
				buf = null;
				return;
			} else {
				errnoEnforce(false);
			}
		}
		buf.length = readAmount;
	}
	
	/// Writes data to the pipe
	void write(const(void)[] buf) {
		while(buf.length > 0) {
			ssize_t numWritten = .write(tracerWriterFd, buf.ptr, buf.length);
			errnoEnforce(numWritten != -1);
			buf = buf[numWritten..$];
		}
	}
}
