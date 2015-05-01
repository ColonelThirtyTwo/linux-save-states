module procinfo;

import std.regex;
import std.range;
import std.c.linux.linux : pid_t;

import models;

public import procinfo.memory;
public import procinfo.tracer;

/// Spawns a process in an environment suitable for TASing and returns a ProcInfo structure.
/// The process will start paused; use `info.tracer.resume` to resume it.
ProcInfo spawn(string[] args) {
	auto tracer = spawnTraced(args);
	ProcInfo info = {
		tracer: tracer,
		memory: ProcMemory(tracer.pid),
	};
	return info;
}

struct ProcInfo {
	ProcTracer tracer;
	ProcMemory memory;
	
	/// Traced process PID.
	pid_t pid() @property {
		return tracer.pid;
	}
	
	/// Saves the process state.
	/// The process should be in a ptrace-stop.
	SaveState saveState(string name) {
		SaveState state = {
			name: name,
			maps: memory.getMaps().array(),
			registers: tracer.getRegisters(),
		};
		return state;
	}
	
	/// Loads a state from a SaveState object to the process' state.
	/// The process should be in a ptrace-stop.
	void loadState(in SaveState state) {
		foreach(ref map; state.maps) {
			if(map.contents.ptr != null)
				memory.writeMapContents(map);
		}
		tracer.setRegisters(state.registers);
	}
	
	invariant {
		assert(tracer.pid == memory.pid);
	}
}

/// Checks if the process is stopped with SIGSTOP.
bool isStopped(in pid_t pid) {
	alias statRE = ctRegex!`^[^\s]+ [^\s]+ (.)`;
	
	auto stat = File("/proc/"~to!string(pid)~"/stat");
	auto line = stat.readln();
	auto match = line.matchFirst(statRE);
	assert(match);
	
	return match[1] == "T";
}
