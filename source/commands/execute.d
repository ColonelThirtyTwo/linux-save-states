/// Contains the `execute` command and the shell for it.
module commands.execute;

import std.stdio;
import std.conv : to, ConvException;
import std.c.linux.linux;
import std.string : chomp, toStringz, fromStringz;
import std.algorithm;
import std.range;
import std.typetuple;
import std.exception : assumeWontThrow;

import d2sqlite3;

import commands : CommandName, Help, CliOnly, ShellOnly;
import models;
import procinfo;
import savefile;
import libevent = bindings.libevent;
version(LineNoise) import bindings.linenoise;

import allcmds = commands.all;
import global;

private struct CommandInterpreter {
	void doCommands() {
		version(LineNoise)
			linenoiseSetCompletionCallback(&completer);
		
		this.doLoop = true;
		writeln("-- Paused --");
		while(doLoop) {
			string line;
			version(LineNoise) {
				line = linenoise("> ").fromStringz.idup;
				if(line.ptr is null)
					break;
			} else {
				write("> ");
				line = readln().chomp("\n");
			}
			
			auto args = line
				.splitter
				.filter!(x => x.length > 0)
				.array
			;
			try {
				this.doCommand(args);
			} catch(CommandContinue ex) {
				return;
			}
		}
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
			
			default:
				writeln("Unknown command");
				return 1;
		}
	}
	
	version(LineNoise) {
		extern(C) static void completer(const(char)* argbuf, linenoiseCompletions* completions) nothrow {
			string arg = assumeWontThrow(argbuf.fromStringz.idup);
			[staticMap!(CommandName, allcmds.ShellCommands)]
				.filter!(cmd => cmd.startsWith(arg))
				.each!(cmd => linenoiseAddCompletion(completions, cmd.toStringz));
		}
	}
}

@("<proc> [args...]")
@(`Executes a process in an environment suitable for TASing.`)
@CliOnly
int cmd_execute(string[] args) {
	import std.c.linux.linux;
	//import bindings.syscalls;
	
	if(args.length == 0) {
		stderr.writeln(Help!cmd_execute);
		return 1;
	}
	if(args[0] == "--help" || args[0] == "-h") {
		writeln(Help!cmd_execute);
		return 0;
	}
	
	if(process !is null) {
		stderr.writeln("Cannot spawn process: a process is already being traced.");
		return 1;
	}
	
	initGl();
	libevent.initEvents();
	
	process = spawn(args);
	process.resume();
	
	auto commands = CommandInterpreter();
	
	try {
		while(true) {
			process.wait();
			commands.doCommands();
			
			process.time.incrementFrame();
			process.time.updateTime(process);
			process.write!false(Wrapper2AppCmd.CMD_CONTINUE);
		}
	} catch(CommandQuit ex) {
		return 0;
	} catch(TraceeExited ex) {
		writeln("+ exited with status ", ex.exitCode);
		return ex.exitCode;
	} catch(TraceeSignaled ex) {
		writeln("+ exited due to signal");
		return 2;
	}
	assert(false);
}

@("")
@("Exits the command shell and continues the tracee")
@ShellOnly
int cmd_continue(string[] args) {
	if(args.length != 0) {
		stderr.writeln(Help!cmd_continue);
		return 1;
	}
	
	throw new CommandContinue();
}
alias cmd_c = cmd_continue;

@("")
@("Exits the command shell and terminates the tracee")
@ShellOnly
int cmd_quit(string[] args) {
	if(args.length != 0) {
		stderr.writeln(Help!cmd_quit);
		return 1;
	}
	
	throw new CommandQuit();
}
alias cmd_q = cmd_quit;

@("[cmd]")
@("Prints help text")
int cmd_help(string[] args) {
	if(args.length == 0) {
		if(process is null)
			writeln(allcmds.PROG_USAGE);
		else
			writeln(allcmds.SHELL_USAGE);
		return 0;
	}
	if(args.length == 1) {
		switch(args[0]) {
			foreach(cmd; allcmds.AllCommands) {
				case CommandName!cmd:
					writeln(Help!(__traits(getMember, allcmds, cmd)));
					return 0;
			}
			
			default:
				stderr.writeln("Unknown command");
				return 1;
		}
	}
	
	stderr.writeln(Help!cmd_help);
	return 1;
}

/// Thrown in a command to exit the shell and resume the tracee
final class CommandContinue : Exception {
	this(string file=__FILE__, size_t line=__LINE__) {
		super("continue", file, line);
	}
}

/// Thrown in a command to close the tracer and tracee.
final class CommandQuit : Exception {
	this(string file=__FILE__, size_t line=__LINE__) {
		super("quit", file, line);
	}
}

