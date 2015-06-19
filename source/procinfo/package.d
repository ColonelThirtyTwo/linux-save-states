/// Functions for inspecting the resources of traced processes.
module procinfo;

import std.regex;
import std.range;
import std.typecons;
import std.c.linux.linux : pid_t;
import std.algorithm : filter;

import models;

public import procinfo.memory;
public import procinfo.tracer;
public import procinfo.cmdpipe;
public import procinfo.files;
public import procinfo.time;

/// Spawns a process in an environment suitable for TASing and returns a ProcInfo structure.
/// The process will start paused; use `info.tracer.resume` to resume it.
ProcInfo spawn(string[] args) {
	CommandPipe cmdpipe = CommandPipe.create();
	
	auto tracer = spawnTraced(args, cmdpipe);
	return new ProcInfo(tracer, cmdpipe);
}

/// Process info structure, which holds several other process-related structures
/// for controlling and getting info from a process.
final class ProcInfo {
	ProcTracer tracer;
	CommandPipe commandPipe;
	Time time;
	
	private this(ProcTracer tracer, CommandPipe commandPipe) {
		this.tracer = tracer;
		this.commandPipe = commandPipe;
	}
	
	/// Traced process PID.
	pid_t pid() @property {
		return tracer.pid;
	}
	
	/// Saves the process state.
	/// The process should be in a ptrace-stop.
	SaveState saveState(string name) {
		SaveState state = {
			name: name,
			maps: readMemoryMaps(pid).array(),
			registers: tracer.getRegisters(),
			files: readFiles(pid).array(),
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
	}
	
	/// Sends a command through the command pipe to the tracee.
	void write(T...)(T vals) {
		this.tracer.resume();
		
		foreach(val; vals)
			this.commandPipe.write(val);
		
		while(this.tracer.wait() != WaitEvent.PAUSE)
			this.tracer.resume();
	}
}

/// Checks if the process is stopped with SIGSTOP.
bool isStopped(in pid_t pid) {
	alias statRE = ctRegex!`^[^\s]+ [^\s]+ (.)`;
	
	auto stat = File("/proc/"~to!string(pid)~"/stat", "reb");
	auto line = stat.readln();
	auto match = line.matchFirst(statRE);
	assert(match);
	
	return match[1] == "T";
}
