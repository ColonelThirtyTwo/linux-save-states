module commands.execute;

import std.stdio;
import std.conv : to, ConvException;
import std.c.linux.linux;
import std.string : chomp;
import std.algorithm;
import std.range;
import std.typetuple;

import d2sqlite3;

import commands : CommandName, Help, CliOnly;
import models;
import procinfo;
import savefile;

import allcmds = commands.all;
import global;

private struct CommandInterpreter {
	void doCommands() {
		this.doLoop = true;
		writeln("-- Paused --");
		while(doLoop) {
			write("> ");
			auto args = readln()
				.chomp("\n")
				.splitter
				.filter!(x => x.length > 0)
				.array
			;
			this.doCommand(args);
		}
		
		process.commandPipe.write(Wrapper2AppCmd.CMD_CONTINUE);
	}
	
private:
	/// set to false to stop the command loop and continue the process
	bool doLoop;
	
	/// Runs one command
	int doCommand(string[] args) {
		if(args.length == 0)
			return 0;
		
		switch(args[0]) {
			foreach(cmd; allcmds.ShellCommands) {
				case CommandName!cmd:
					return __traits(getMember, allcmds, cmd)(args[1..$]);
			}
			
			case "h":
			case "help":
				writeln(allcmds.SHELL_USAGE);
				return 0;
			
			case "c":
			case "continue":
				if(args.length > 1)
					writeln("Usage: c[ontinue]\nContinues execution of the traced process.");
				else
					doLoop = false;
				return 0;
			
			default:
				writeln("Unknown command");
				return 1;
		}
	}
}

@("<proc> [args...]")
@(`Executes a process in an environment suitable for TASing.`)
@CliOnly
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
	
	if(!process.isNull) {
		stderr.writeln("Cannot spawn process: a process is already being traced.");
		return 1;
	}
	
	process = spawn(args);
	process.tracer.resume();
	
	// true if in syscall
	bool inSyscall = false;
	// true if we got SIGTRAP in a syscall and we should stop when the syscall exits.
	bool shouldStop = false;
	
	auto commands = CommandInterpreter();
	
	try {
		while(true) {
			auto ev = process.tracer.wait();
			final switch(ev) {
			case WaitEvent.PAUSE:
				if(inSyscall)
					// `kill(getpid(), SIGTRAP)` will stop the process while in a system call, during which
					// the process shouldn't be saved, so delay stopping until the syscall exits.
					shouldStop = true;
				else
					commands.doCommands();
				process.tracer.resume();
				break;
			case WaitEvent.SYSCALL:
				if(!inSyscall) {
					// entering syscall
					//writeln("+ syscall: ", process.tracer.getSyscall().to!string);
					inSyscall = true;
				} else {
					// exiting syscall
					inSyscall = false;
					if(shouldStop) {
						commands.doCommands();
						shouldStop = false;
					}
				}
				process.tracer.resume();
				break;
			}
		}
	} catch(TraceeExited ex) {
		writeln("+ exited with status ", ex.exitCode);
		return ex.exitCode;
	} catch(TraceeSignaled ex) {
		writeln("+ exited due to signal");
		return 2;
	}
	assert(false);
}
