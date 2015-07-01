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

import commands : CommandName, Help, CliOnly;
import models;
import procinfo;
import procinfo.gl;
import savefile;
import signals = signals;
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
			this.doCommand(args);
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
			
			case "q":
			case "quit":
				throw new QuitException();
			
			default:
				writeln("Unknown command");
				return 1;
		}
	}
	
	version(LineNoise) {
		extern(C) static void completer(const(char)* argbuf, linenoiseCompletions* completions) nothrow {
			string arg = assumeWontThrow(argbuf.fromStringz.idup);
			([staticMap!(CommandName, allcmds.ShellCommands)]
				~ ["c", "continue", "h", "help", "q", "quit"])
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
	
	OpenGLState.init();
	
	process = spawn(args);
	signals.initSignals();
	process.resume();
	
	auto commands = CommandInterpreter();
	
	try {
		while(true) {
			process.wait();
			commands.doCommands();
			
			process.time.incrementFrame();
			process.time.updateTime(process);
			process.glState.pollEvents();
			process.write!false(Wrapper2AppCmd.CMD_CONTINUE);
		}
	} catch(QuitException ex) {
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

/// Thrown by q[uit] to terminate the loop
final class QuitException : Exception {
	this(string file=__FILE__, size_t line=__LINE__) {
		super("quit", file, line);
	}
}
