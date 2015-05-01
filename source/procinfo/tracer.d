
module procinfo.tracer;

import std.exception : errnoEnforce;
import std.c.linux.linux;
import std.process : execvp;
import core.stdc.config : c_ulong, c_long;

enum PTraceRequest : int {
	PTRACE_TRACEME = 0,
	PTRACE_PEEKTEXT = 1,
	PTRACE_PEEKDATA = 2,
	PTRACE_PEEKUSER = 3,
	PTRACE_POKETEXT = 4,
	PTRACE_POKEDATA = 5,
	PTRACE_POKEUSER = 6,
	PTRACE_CONT = 7,
	PTRACE_KILL = 8,
	PTRACE_SINGLESTEP = 9,
	PTRACE_GETREGS = 12,
	PTRACE_SETREGS = 13,
	PTRACE_GETFPREGS = 14,
	PTRACE_SETFPREGS = 15,
	PTRACE_ATTACH = 16,
	PTRACE_DETACH = 17,
	PTRACE_GETFPXREGS = 18,
	PTRACE_SETFPXREGS = 19,
	PTRACE_SYSCALL = 24,
	PTRACE_SETOPTIONS = 0x4200,
	PTRACE_GETEVENTMSG = 0x4201,
	PTRACE_GETSIGINFO = 0x4202,
	PTRACE_SETSIGINFO = 0x4203,
	PTRACE_GETREGSET = 0x4204,
	PTRACE_SETREGSET = 0x4205,
	PTRACE_SEIZE = 0x4206,
	PTRACE_INTERRUPT = 0x4207,
	PTRACE_LISTEN = 0x4208,
	PTRACE_PEEKSIGINFO = 0x4209,
};

enum PTraceOptions : int {
	PTRACE_O_TRACESYSGOOD = 0x00000001,
	PTRACE_O_TRACEFORK = 0x00000002,
	PTRACE_O_TRACEVFORK = 0x00000004,
	PTRACE_O_TRACECLONE = 0x00000008,
	PTRACE_O_TRACEEXEC = 0x00000010,
	PTRACE_O_TRACEVFORKDONE = 0x00000020,
	PTRACE_O_TRACEEXIT = 0x00000040,
	PTRACE_O_TRACESECCOMP = 0x00000080,
	PTRACE_O_EXITKILL = 0x00100000,
	PTRACE_O_MASK = 0x001000ff,
};

private extern(C) {
	enum ADDR_NO_RANDOMIZE = 0x0040000;;
	int personality(c_ulong);
	c_long ptrace(PTraceRequest, pid_t, void*, void*);
}

/// Spawns a process in an environment suitable for TASing and traces it.
/// The process will start paused.
ProcTracer spawnTraced(string[] args)
in {
	assert(args.length >= 1);
} body {
	// Disable GC in case it uses signals, which would be caught by ptrace.
	core.memory.GC.disable();
	scope(exit) core.memory.GC.enable();
	
	int pid = fork();
	errnoEnforce(pid != -1);
	if(pid == 0) {
		try {
			// In fork, set up and run wrapped process.
			
			// Disable ASLR to place memory in repeatable positions
			errnoEnforce(personality(ADDR_NO_RANDOMIZE) != -1);
			// Trace self
			errnoEnforce(ptrace(PTraceRequest.PTRACE_TRACEME, 0, null, null) != -1);
			// Execute
			errnoEnforce(execvp(args[0], args) != 0);
			assert(false);
		} catch(Exception ex) {
			// Don't run destructors in forked process; database/file destructors won't be valid.
			import std.stdio : stderr;
			import core.stdc.stdlib : exit;
			
			stderr.writeln(ex);
			exit(1);
			assert(false);
		}
	} else {
		// Not in fork; set up options
		import std.stdio : writeln; writeln(pid);
		
		auto tracer = ProcTracer(pid);
		tracer.wait();
		
		errnoEnforce(ptrace(PTraceRequest.PTRACE_SETOPTIONS, pid, null,
			cast(void*) (PTraceOptions.PTRACE_O_EXITKILL | PTraceOptions.PTRACE_O_TRACESYSGOOD)) != -1);
		
		return ProcTracer(pid);
	}
}

/// Structure for tracing a process using ptrace.
/// Create by using `spawnTraced`
struct ProcTracer {
	immutable pid_t pid;
	
	private this(pid_t pid) {
		this.pid = pid;
	}
	
	/// Calls waitpid on the child process and returns the status.
	int wait() {
		int status;
		int waitedPID = waitpid(pid, &status, 0);
		errnoEnforce(waitedPID != -1);
		assert(waitedPID == pid);
		return status;
	}
	
	/// Continues a process in a ptrace stop.
	/// If `untilSyscall` is true, then the process will continue until the next system call (PTRACE_SYSCALL),
	/// otherwise it will continue until it receives a signal or other condition (PTRACE_CONT).
	void resume(bool untilSyscall=true) {
		errnoEnforce(ptrace(untilSyscall ? PTraceRequest.PTRACE_SYSCALL : PTraceRequest.PTRACE_CONT,
			pid, null, null) != -1);
	}
}
