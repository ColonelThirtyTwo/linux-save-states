/// Functions for setting up signals and getting a signal file descriptor
module signals;

import std.c.linux.linux;
import core.sys.linux.sys.signalfd;
import std.exception : errnoEnforce;

private int _sigfd = -1;

/// Gets the signal file descriptor that listens for SIGCHLD. See signalfd (2).
/// `initSignals` must be called before getting this property.
int sigfd() @property nothrow @nogc {
	assert(_sigfd != -1);
	return _sigfd;
}

/// Initializes the signal file descriptor.
void initSignals() {
	assert(_sigfd == -1);
	
	sigset_t signals;
	sigemptyset(&signals);
	sigaddset(&signals, SIGCHLD);
	
	// block SIGCHLD so that the signalfd can process it
	errnoEnforce(sigprocmask(SIG_BLOCK, &signals, null) != -1);
	
	_sigfd = signalfd(-1, &signals, SFD_CLOEXEC);
	errnoEnforce(_sigfd != -1);
}
