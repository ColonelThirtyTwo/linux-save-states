
/// High-level tracee manipulation
module procinfo.proc;

import std.range;
import std.typecons;
import std.algorithm;
import std.variant;
import std.c.linux.linux;
import core.sys.linux.sys.signalfd : signalfd_siginfo;
import poll;

import bindings.libevent;
import procinfo;
import models;
import signals = signals;
import bindings.libevent;

private alias linux_read = read;

/// Spawns a process in an environment suitable for TASing and returns a ProcInfo structure.
/// The process will start paused; use `info.tracer.resume` to resume it.
ProcInfo spawn(string[] args) {
	auto cmdpipe = CommandPipe.create();
	auto glpipe = CommandPipe.create();
	
	auto tracer = spawnTraced(args, cmdpipe, glpipe);
	return new ProcInfo(tracer, cmdpipe, glpipe);
}

/// Process info structure, which holds several other process-related structures
/// for controlling and getting info from a process.
final class ProcInfo {
	private ProcTracer tracer;
	private CommandPipe commandPipe;
	private CommandPipe glPipe;
	private CommandDispatcher commandDispatcher;
	private Events events;
	Time time;
	OpenGLState glState;
	
	private this(ProcTracer tracer, CommandPipe commandPipe, CommandPipe glPipe) {
		this.tracer = tracer;
		this.commandPipe = commandPipe;
		this.glPipe = glPipe;
		
		events = new Events();
		events.addFile(commandPipe.readFD);
		events.addSignal(SIGCHLD);
	}
	
	/// Traced process PID.
	pid_t pid() @property const pure nothrow @nogc {
		return tracer.pid;
	}
	
	/// Resumes the process.
	void resume() {
		tracer.resume();
	}
	
	/// Waits until the process pauses.
	/// This also handles any commands that the process sends through the command pipe, unlike `tracer.wait`.
	/// Can also throw one of `TraceeExited`, `TraceeSignaled`, or `UnknownEvent`; see `procinfo.tracer`
	void wait() {
		bool continuePolling = true;
		while(continuePolling) {
			auto ev = events.next;
			
			assert(ev.hasValue, "no events left");
			
			ev.visit!(
				(FileEvent ev) {
					assert(ev.fd == commandPipe.readFD);
					assert(ev.readable);
					
					Nullable!App2WrapperCmd cmd;
					while(!(cmd = commandPipe.peekCommand()).isNull)
						commandDispatcher.execute(cmd, this);
				},
				(SignalEvent ev) {
					assert(ev.signal == SIGCHLD);
					
					auto waitEv = tracer.wait();
					assert(waitEv == WaitEvent.PAUSE);
					
					continuePolling = false;
				},
				(CustomEvent ev) {
					assert(false);
				},
			);
		}
		/+
		while(true) {
			auto readyFDs = dpoll(only(commandPipe.readFD, signals.sigfd));
			
			if(readyFDs.save.canFind(commandPipe.readFD)) {
				// Have some commands; execute them until empty
				Nullable!App2WrapperCmd cmd;
				while(!(cmd = commandPipe.peekCommand()).isNull)
					commandDispatcher.execute(cmd, this);
			}
			
			if(readyFDs.save.canFind(signals.sigfd)) {
				// Got a SIGCHLD, call wait to check on process
				signalfd_siginfo info;
				auto numRead = linux_read(signals.sigfd, &info, info.sizeof);
				errnoEnforce(numRead != -1);
				assert(numRead == info.sizeof);
				
				assert(info.ssi_signo == SIGCHLD);
				assert(info.ssi_pid == pid);
				
				// tracer.wait will throw exceptions if the process terminated
				auto ev = tracer.wait();
				assert(ev == WaitEvent.PAUSE);
				return;
			}
		}
		+/
	}
	
	/// Saves the process state.
	/// The process should be in a ptrace-stop.
	SaveState saveState(string name) {
		SaveState state = {
			name: name,
			maps: readMemoryMaps(pid).array(),
			registers: tracer.getRegisters(),
			files: readFiles(pid).array(),
			
			windowSize: glState.hasWindow ?
				typeof(SaveState.windowSize)(glState.windowSize) :
				typeof(SaveState.windowSize)(),
		};
		return state;
	}
	
	/// Loads a state from a SaveState object to the process' state.
	/// The process should be in a ptrace-stop.
	void loadState(in SaveState state) {
		this.setBrk(state.brk);
		writeMemoryMaps(pid, state.maps.filter!(x => x.contents.ptr != null));
		tracer.setRegisters(state.registers);
		loadFiles(this, state.files);
		
		time.loadTime(state);
		time.updateTime(this);
		
		if(state.windowSize.isNull && glState.hasWindow)
			glState.closeWindow();
		else if(!state.windowSize.isNull) {
			if(glState.hasWindow)
				glState.resizeWindow(state.windowSize);
			else
				glState.openWindow(state.windowSize);
		}
	}
	
	/// Sends a command through the command pipe to the tracee.
	/// By default, this waits for the tracee to read the data and finish processing. Set waitForResponse to false to not wait.
	void write(bool waitForResponse = true, T...)(T vals) {
		this.resume();
		
		foreach(val; vals)
			this.commandPipe.write(val);
		
		static if(waitForResponse)
			this.wait();
	}
	
	/// Reads data through the command pipe from the tracee.
	Tuple!Data read(Data...)() {
		Tuple!Data result;
		foreach(i, T; Data)
			result[i] = this.commandPipe.read!T();
		return result;
	}
}
