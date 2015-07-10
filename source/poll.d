/// Higher-level poll interface
module poll;

import std.algorithm;
import std.range;
import std.exception;
import core.sys.posix.poll;

/// Argument and return value of dpoll that contains the file descriptor and events.
struct PollEntry {
	/// The file descriptor to wait on or that has activity
	int fd;
	/// The events to wait on or the ready activity of the file descriptor
	PollEvent events;
}

/// Events to wait for/return
enum PollEvent {
	IN = POLLIN,
	PRI = POLLPRI,
	OUT = POLLOUT,
//	RDHUP = POLLRDHUP,
	ERR = POLLERR,
	HUP = POLLHUP,
	NVAL = POLLNVAL,
}

/// D-friendly wrapper for poll.
/// Returns an input range containing PollEntry structures that have events set on them.
auto dpoll(T)(T files, int timeout=-1)
if(isInputRange!T && is(ElementType!T : PollEntry) && !isInfinite!T) {
	pollfd[] fds = files
		.map!(file => pollfd(file.fd, cast(short)file.events, 0))
		.array
	;
	
	int numEvents = poll(fds.ptr, fds.length, timeout);
	errnoEnforce(numEvents != -1);
	
	debug assert(fds.count!(fd => fd.revents != 0) == numEvents);
	
	return fds
		.filter!(fd => fd.revents != 0)
		.map!(fd => PollEntry(fd.fd, cast(PollEvent) fd.revents))
		.takeExactly(numEvents)
	;
}

/// A shorter form of dpoll that listens for read-available file descriptors and returns a range of file descriptors that are readable.
auto dpoll(T)(T files, int timeout=-1)
if(isInputRange!T && is(ElementType!T : int) && !isInfinite!T) {
	return dpoll(files.map!(fd => PollEntry(fd, PollEvent.IN)), timeout).map!(ev => ev.fd);
}
