
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
import procinfo.pipe;
import models;
import opengl.gldispatch;
import opengl.idmaps;
import bindings.libevent;

/// Spawns a process in an environment suitable for TASing and returns a ProcInfo structure.
/// The process will start paused; use `info.tracer.resume` to resume it.
ProcInfo spawn(string[] args) {
	auto cmdpipe = CommandPipe.create();
	auto glpipe = Pipe(false);
	
	auto tracer = spawnTraced(args, cmdpipe, glpipe);
	return new ProcInfo(tracer, cmdpipe, glpipe);
}

/++ Process info structure, which holds several other process-related structures
 + for controlling and getting info from a process.
++/
final class ProcInfo {
	private ProcTracer tracer;
	private CommandPipe commandPipe;
	private Pipe glPipe;
	private CommandDispatcher commandDispatcher;
	private Events events;
	private GlDispatch glDispatch;
	private IdMaps idmaps;
	Time time;
	GlWindow window;
	
	private this(ProcTracer tracer, CommandPipe commandPipe, Pipe glPipe) {
		this.tracer = tracer;
		this.commandPipe = commandPipe;
		this.glPipe = glPipe;
		
		events = new Events();
		events.addFile(commandPipe.readFD);
		events.addFile(glPipe.readFD);
		events.addFile(x11EventsFd);
		events.addSignal(SIGCHLD);
		
		window = new GlWindow();
		idmaps = new IdMaps();
		glDispatch = new GlDispatch(glPipe, idmaps);
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
		// If true, the tracee is running, and we should wait for it.
		// If false, the tracee is paused, and we are clearing out the backlog of commands
		bool continueWaiting = true;
		Event ev;
		while((ev = events.next(continueWaiting)).hasValue) {
			ev.visit!(
				(FileEvent ev) {
					if(ev.fd == commandPipe.readFD)
						return onTracerCommandAvailable();
					else if(ev.fd == glPipe.readFD)
						return onGLCommandAvailable();
					else if(ev.fd == x11EventsFd)
						return onXEventAvailable();
					else
						assert(false);
				},
				(SignalEvent ev) {
					assert(ev.signal == SIGCHLD);
					
					auto waitEv = tracer.wait();
					waitEv.visit!(
						(Paused _) { continueWaiting = false; },
						(Signaled ev) { tracer.resume(ev.signal); }
					);
				},
				(CustomEvent ev) {
					assert(false);
				},
			);
		}
		assert(!continueWaiting, "Unexpectedly ran out of event sources");
		glDispatch.poll();
	}
	
	private void onTracerCommandAvailable() {
		Nullable!App2WrapperCmd cmd;
		while(!(cmd = commandPipe.peekCommand()).isNull)
			commandDispatcher.execute(cmd, this);
	}
	private void onGLCommandAvailable() {
		glDispatch.poll();
	}
	private void onXEventAvailable() {
		window.pollEvents();
	}
	
	
	/// Saves the process state.
	/// The process should be in a ptrace-stop.
	SaveState saveState(string name) {
		SaveState state = new SaveState();
		state.name = name;
		state.maps = readMemoryMaps(pid).array();
		state.registers = tracer.getRegisters();
		state.files = readFiles(pid).array();
		state.windowSize = window.isOpen ?
				typeof(SaveState.windowSize)(window.size) :
				typeof(SaveState.windowSize)();
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
		
		if(state.windowSize.isNull && window.isOpen)
			window.close();
		else if(!state.windowSize.isNull) {
			if(window.isOpen)
				window.resize(state.windowSize);
			else
				window.open(state.windowSize);
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
