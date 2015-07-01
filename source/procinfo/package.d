/// Functions for inspecting the resources of traced processes.
module procinfo;

public import procinfo.commands;
public import procinfo.cmdpipe;
public import procinfo.memory;
public import procinfo.tracer;
public import procinfo.files;
public import procinfo.time;
public import procinfo.cmddispatch;
public import procinfo.gl;
public import procinfo.proc;


/+
/// Checks if the process is stopped with SIGSTOP.
bool isStopped(in pid_t pid) {
	alias statRE = ctRegex!`^[^\s]+ [^\s]+ (.)`;
	
	auto stat = File("/proc/"~to!string(pid)~"/stat", "reb");
	auto line = stat.readln();
	auto match = line.matchFirst(statRE);
	assert(match);
	
	return match[1] == "T" || match[1] == "t";
}
+/
