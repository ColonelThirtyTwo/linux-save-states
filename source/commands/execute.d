module commands.execute;

import std.stdio;
import std.conv : to, ConvException;
import std.c.linux.linux;

import d2sqlite3;

import commands;
import models;
import procinfo;

@("<proc> [args...]")
@(`Executes a process in an environment suitable for TASing.`)
int cmd_execute(string[] args) {
	import std.c.linux.linux;
	import syscalls;
	
	if(args.length == 0) {
		stderr.writeln(Help!cmd_execute);
		return 1;
	}
	if(args[0] == "--help" || args[0] == "-h") {
		writeln(Help!cmd_execute);
		return 0;
	}
	
	auto proc = spawn(args);
	proc.tracer.resume();
	
	bool inSyscall = false;
	
	while(true) {
		int status = proc.tracer.wait();
		
		if(WIFEXITED(status))
			return WEXITSTATUS(status);
		if(WIFSIGNALED(status))
			return 2;
		
		if(!WIFSTOPPED(status)) {
			proc.tracer.resume();
			continue;
		}
		
		if(WSTOPSIG(status) == SIGTRAP) {
			writeln("+ Got SIGTRAP, paused.");
			stdout.write("Press enter to continue.");
			readln();
			proc.tracer.resume();
		} else if(WSTOPSIG(status) == (SIGTRAP | 0x80)) {
			if(inSyscall)
				inSyscall = false;
			else {
				writeln("+ Syscall: ", proc.tracer.getSyscall().to!string);
				inSyscall = true;
			}
			proc.tracer.resume();
		} else {
			proc.tracer.resume(WSTOPSIG(status));
		}
	}
	
	assert(false);
}
