/// Spawning and controlling a traced process.
module procinfo.tracer;

import std.algorithm;
import std.range;
import std.variant;
import std.conv : text, to;
import std.exception : errnoEnforce;
import std.path : absolutePath;
import std.file : getcwd;
import std.process : execvpe, environment;
import std.format;
import std.c.linux.linux;
import core.sys.linux.errno;

import models : Registers;
import bindings.syscalls;
import bindings.ptrace;
import procinfo.pipe;
import procinfo.cmdpipe;

/// Creates an environment for the tracee, setting up `LD_PRELOAD` to load the tracee library.
private string[] getTraceeEnv() {
	auto envAA = environment.toAA();
	envAA["LD_PRELOAD"] = absolutePath("libsavestates.so");
	envAA["LD_LIBRARY_PATH"] = getcwd();
	return envAA
		.byPair
		.map!(pair => pair[0] ~ "=" ~ pair[1])
		.array;
}


/// Spawns a process in an environment suitable for TASing and traces it.
/// The process will start paused.
ProcTracer spawnTraced(string[] args, Pipe cmdPipe, Pipe glPipe)
in {
	assert(args.length >= 1);
} body {
	auto env = getTraceeEnv();
	
	// Disable GC in case it uses signals, which would be caught by ptrace.
	core.memory.GC.disable();
	scope(exit) core.memory.GC.enable();
	
	int pid = fork();
	errnoEnforce(pid != -1);
	if(pid == 0) {
		// In fork, set up and run wrapped process.
		try {
			// Disable ASLR to place memory in repeatable positions
			errnoEnforce(personality(ADDR_NO_RANDOMIZE) != -1);
			
			// Setup command pipes
			cmdPipe.setupTraceePipes(SpecialFileDescriptors.TRACEE_READ_FD, SpecialFileDescriptors.TRACEE_WRITE_FD);
			glPipe.setupTraceePipes(SpecialFileDescriptors.GL_READ_FD, SpecialFileDescriptors.GL_WRITE_FD);
			
			// Trace self
			errnoEnforce(ptrace(PTraceRequest.PTRACE_TRACEME, 0, null, null) != -1);
			// Execute
			errnoEnforce(execvpe(args[0], args, env) != 0);
		} catch(Exception ex) {
			// Don't run destructors in forked process; closing the database would be dangerous
			import std.stdio : stderr;
			import core.stdc.stdlib : exit;
			
			stderr.writeln(ex);
			exit(1);
		}
		assert(false);
	}
	
	cmdPipe.closeTraceePipes();
	glPipe.closeTraceePipes();
	
	// Not in fork; set up ptrace options
	auto tracer = ProcTracer(pid);
	tracer.wait();
	
	errnoEnforce(ptrace(PTraceRequest.PTRACE_SETOPTIONS, pid, null,
		cast(void*) (PTraceOptions.PTRACE_O_EXITKILL | PTraceOptions.PTRACE_O_TRACESYSGOOD)) != -1);
	
	return tracer;
}

/++ Structure for controlling a process using ptrace.
 +
 + Created via spawnTraced.
++/
struct ProcTracer {
	pid_t pid;
	debug private bool isPaused = false;
	
	private this(pid_t pid) {
		this.pid = pid;
	}
	
	/// Waits for the tracee to pause after a call to resume.
	/// Returns a WaitEvent describing what caused the process to stop, or throws one of TraceeExited, TraceeSignaled, or UnknownEvent.
	WaitEvent wait(bool nohang=false) {
		debug assert(!isPaused, "wait called on paused process");
		
		int status;
		//int waitedPID = waitpid(pid, &status, nohang ? WNOHANG : 0);
		int waitedPID = waitpid(-1, &status, nohang ? WNOHANG : 0);
		errnoEnforce(waitedPID != -1);
		if(waitedPID == 0)
			return WaitEvent();
		assert(waitedPID == pid, "Unexpected result from waitpid, expected %d, got %d".format(pid, waitedPID));
		
		if(WIFEXITED(status))
			throw new TraceeExited(WEXITSTATUS(status));
		else if(WIFSIGNALED(status))
			throw new TraceeSignaled(WTERMSIG(status));
		else if(WIFSTOPPED(status)) {
			debug isPaused = true;
		
			if(WSTOPSIG(status) == SIGTRAP)
				return WaitEvent(Paused());
			else if(WSTOPSIG(status) == (SIGTRAP | 0x80))
				assert(false); // Not monitoring syscalls
			else {
				return WaitEvent(Signaled(WSTOPSIG(status)));
			}
		} else {
			throw new UnknownEvent(status);
		}
	}
	
	/++ Continues a process in a ptrace stop.
	 +
	 + If `untilSyscall` is true, then the process will continue until the next system call (PTRACE_SYSCALL),
	 + otherwise it will continue until it receives a signal or other condition (PTRACE_CONT).
	++/
	void resume(uint signal=0, bool untilSyscall=false) {
		debug assert(isPaused, "wait called on paused process");
		
		auto err = ptrace(untilSyscall ? PTraceRequest.PTRACE_SYSCALL : PTraceRequest.PTRACE_CONT,
			pid, null, cast(void*) signal);
		if(err == -1 && errno == ESRCH) {
			auto ev = this.wait(true);
			assert(false, "Got "~to!string(ev));
		}
		
		debug isPaused = false;
		
		errnoEnforce(err != -1);
	}
	
	/// Peeks at the process' registers for the system call that the process is executing.
	/// The process must be in a ptrace-stop.
	SysCall getSyscall() {
		user_regs_struct regs;
		errnoEnforce(ptrace(PTraceRequest.PTRACE_GETREGS, pid, null, &regs) != -1);
		version(X86)
			return cast(SysCall) (regs.orig_eax);
		else
			return cast(SysCall) (regs.orig_rax);
	}
	
	/// Returns the process' registers.
	/// The process must be in a ptrace-stop.
	Registers getRegisters() {
		Registers regs;
		errnoEnforce(ptrace(PTraceRequest.PTRACE_GETREGS, pid, null, &regs.general) != -1);
		errnoEnforce(ptrace(PTraceRequest.PTRACE_GETFPREGS, pid, null, &regs.floating) != -1);
		return regs;
	}
	
	/// Sets the process' registers.
	/// The process must be in a ptrace-stop.
	void setRegisters(in Registers regs) {
		// ptrace doesn't modify the registers struct here, so it's ok to cast away const.
		errnoEnforce(ptrace(PTraceRequest.PTRACE_SETREGS, pid, null, &(cast(Registers)regs).general) != -1);
		errnoEnforce(ptrace(PTraceRequest.PTRACE_SETFPREGS, pid, null, &(cast(Registers)regs).floating) != -1);
	}
}

// ////////////////////////////////////////////////////////////////////////////////////////////

/// Returned by wait when the tracee pauses normally.
struct Paused {}
/// Returned by wait when the tracee pauses due to a received signal.
struct Signaled {
	int signal;
}

/// Return value of $(D Tracer.wait)
alias WaitEvent = Algebraic!(Paused, Signaled);

/// Thrown by wait when the traced process exits normally.
final class TraceeExited : Exception {
	const int exitCode;
	
	//this(string msg, string file = null, size_t line = 0)
	this(int code, string file=__FILE__, size_t line=__LINE__) {
		super(text("Tracee terminated with code ", code), file, line);
		exitCode = code;
	}
}

/// Thrown by wait when the traced process terminates via a signal.
final class TraceeSignaled : Exception {
	const int signal;
	
	this(int signal, string file=__FILE__, size_t line=__LINE__) {
		super(text("Tracee terminated via signal 0x", signal.to!string(16)), file, line);
		this.signal = signal;
	}
}

/// Thrown by wait when an unknown event was received.
final class UnknownEvent : Exception {
	const int status;
	
	this(int status, string file=__FILE__, size_t line=__LINE__) {
		super(text("Received unknown status from wait: 0x", status.to!string(16)), file, line);
		this.status = status;
	}
}
