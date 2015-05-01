
module procinfo.tracer;

import std.exception : errnoEnforce;
import std.c.linux.linux;
import std.process : execvp;
import core.stdc.config : c_ulong, c_long;
import syscalls;

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
	void resume(uint signal=0, bool untilSyscall=true) {
		errnoEnforce(ptrace(untilSyscall ? PTraceRequest.PTRACE_SYSCALL : PTraceRequest.PTRACE_CONT,
			pid, null, cast(void*) signal) != -1);
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
		// ptrace doesn't modify the registers here, so it's ok to cast away const.
		errnoEnforce(ptrace(PTraceRequest.PTRACE_SETREGS, pid, null, &(cast(Registers)regs).general) != -1);
		errnoEnforce(ptrace(PTraceRequest.PTRACE_SETFPREGS, pid, null, &(cast(Registers)regs).floating) != -1);
	}
}

// ////////////////////////////////////////////////////////////////////////////////////////////

/// PTrace commands. See ptrace(2) for more info.
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

/// Options for PTRACE_SETOPTIONS. See ptrace(2) for more info.
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

version(X86) {
	// TODO: FPX regs
	struct user_fpregs_struct
	{
		c_long cwd;
		c_long swd;
		c_long twd;
		c_long fip;
		c_long fcs;
		c_long foo;
		c_long fos;
		c_long[20] st_space;
	};
	struct user_regs_struct
	{
		c_long ebx;
		c_long ecx;
		c_long edx;
		c_long esi;
		c_long edi;
		c_long ebp;
		c_long eax;
		c_long xds;
		c_long xes;
		c_long xfs;
		c_long xgs;
		c_long orig_eax;
		c_long eip;
		c_long xcs;
		c_long eflags;
		c_long esp;
		c_long xss;
	};
} else version (X86_64) {
	
	struct user_fpregs_struct
	{
		ushort cwd;
		ushort swd;
		ushort ftw;
		ushort fop;
		c_ulong rip;
		c_ulong rdp;
		uint mxcsr;
		uint mxcr_mask;
		uint[32] st_space;   /* 8*16 bytes for each FP-reg = 128 bytes */
		uint[64] xmm_space;  /* 16*16 bytes for each XMM-reg = 256 bytes */
		uint[24] padding;
	};

	struct user_regs_struct
	{
		c_ulong r15;
		c_ulong r14;
		c_ulong r13;
		c_ulong r12;
		c_ulong rbp;
		c_ulong rbx;
		c_ulong r11;
		c_ulong r10;
		c_ulong r9;
		c_ulong r8;
		c_ulong rax;
		c_ulong rcx;
		c_ulong rdx;
		c_ulong rsi;
		c_ulong rdi;
		c_ulong orig_rax;
		c_ulong rip;
		c_ulong cs;
		c_ulong eflags;
		c_ulong rsp;
		c_ulong ss;
		c_ulong fs_base;
		c_ulong gs_base;
		c_ulong ds;
		c_ulong es;
		c_ulong fs;
		c_ulong gs;
	};

} else static assert(false, "Unsupported architecture.");

/// Holds the contents of the (architecture dependent) registers.
struct Registers {
	user_regs_struct general;
	user_fpregs_struct floating;
}

private extern(C) {
	enum ADDR_NO_RANDOMIZE = 0x0040000;;
	int personality(c_ulong);
	c_long ptrace(PTraceRequest, pid_t, void*, void*);
}

