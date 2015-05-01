
#include <stdlib.h>
#include <sys/types.h>
#include <signal.h>
#include <unistd.h>

/// Pauses the process and waits for the tracer to resume it.
/// The game's state can be saved during this pause.
void lss_pause() {
	kill(getpid(), SIGTRAP);
}
