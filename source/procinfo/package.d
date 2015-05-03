module procinfo;

import std.regex;
import std.range;
import std.c.linux.linux : pid_t;
import std.algorithm : filter;

import models;

public import procinfo.memory;
public import procinfo.tracer;
public import procinfo.cmdpipe;
public import procinfo.files;

/// Spawns a process in an environment suitable for TASing and returns a ProcInfo structure.
/// The process will start paused; use `info.tracer.resume` to resume it.
ProcInfo spawn(string[] args) {
	CommandPipe cmdpipe = CommandPipe.create();
	
	auto tracer = spawnTraced(args, cmdpipe);
	ProcInfo info = {
		tracer: tracer,
		commandPipe: cmdpipe,
	};
	return info;
}

struct ProcInfo {
	ProcTracer tracer;
	CommandPipe commandPipe;
	
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
		writeMemoryMaps(pid, state.maps.filter!(x => x.contents.ptr != null));
		tracer.setRegisters(state.registers);
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
