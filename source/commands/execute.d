module commands.execute;

import std.stdio;
import std.conv : to, ConvException;
import std.c.linux.linux;
import std.string : chomp;
import std.algorithm;
import std.range;
import std.typetuple;

import d2sqlite3;

import commands : FilterCommands, CommandName, Help;
import models;
import procinfo;
import savefile;

private struct CommandInterpreter {
	this(SaveStatesFile f, ProcInfo p) {
		this.saveStatesFile = f;
		this.proc = p;
	}
	
	void doCommands() {
		this.doLoop = true;
		
		while(doLoop) {
			this.write("> ");
			auto args = readln()
				.chomp("\n")
				.splitter
				.filter!(x => x.length > 0)
				.array
			;
			this.doCommand(args);
		}
	}

private:
	SaveStatesFile saveStatesFile;
	ProcInfo proc;
	
	// set to false to stop the command loop and continue the process
	bool doLoop;
	
	void writeln(T...)(T t) {
		return stdout.writeln("+ ", t);
	}
	void write(T...)(T t) {
		return stdout.write("+ ", t);
	}
	
	void doCommand(string[] args) {
		enum AllCommands = FilterCommands!(__traits(allMembers, CommandInterpreter));
		
		if(args.length == 0)
			return;
		
		switch(args[0]) {
			foreach(cmd; AllCommands) {
				case CommandName!cmd:
					return __traits(getMember, this, cmd)(args[1..$]);
			}
			default:
				this.writeln("Unknown command");
		}
	}
	
	// /////////////////////////////////////////////////////////
	
	@("")
	@("Resumes execution of the program.")
	void cmd_continue(string[] args) {
		if(args.length != 0)
			return this.writeln("Usage: c[ontinue]");
		doLoop = false;
	}
	alias cmd_c = cmd_continue;
	
	@("<label>")
	@(`Saves the state.`)
	void cmd_save(string[] args) {
		if(args.length != 1)
			return this.writeln("Usage: s[ave] <label>");
		saveStatesFile.db.begin();
		scope(success) saveStatesFile.db.commit();
		scope(failure) if(!saveStatesFile.db.isAutoCommit) saveStatesFile.db.rollback();
		
		saveStatesFile.writeState(proc.saveState(args[0]));
		
		this.writeln("state saved");
	}
	alias cmd_s = cmd_save;
	
	@("<label>")
	@(`Loads a state`)
	void cmd_load(string[] args) {
		if(args.length != 1)
			return this.writeln("Usage: l[oad] <label>");
		saveStatesFile.db.begin();
		scope(success) saveStatesFile.db.commit();
		scope(failure) if(!saveStatesFile.db.isAutoCommit) saveStatesFile.db.rollback();
		
		auto state = saveStatesFile.loadState(args[0]);
		if(state.isNull)
			return this.writeln("No such state.");
		proc.loadState(state.get);
		
		this.writeln("state loaded");
	}
}

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
	
	auto saveStatesFile = SaveStatesFile("savestates.db");
	
	auto proc = spawn(args);
	proc.tracer.resume();
	
	// true if in syscall
	bool inSyscall = false;
	// true if we got SIGTRAP in a syscall and we should stop when the syscall exits.
	bool shouldStop = false;
	
	auto commands = CommandInterpreter(saveStatesFile, proc);
	
	while(true) {
		int status = proc.tracer.wait();
		
		// Check if exited
		if(WIFEXITED(status)) {
			stdout.writeln("+ exited with status ", WEXITSTATUS(status));
			return WEXITSTATUS(status);
		}
		if(WIFSIGNALED(status)) {
			stdout.writeln("+ exited due to signal");
			return 2;
		}
		
		if(!WIFSTOPPED(status)) {
			proc.tracer.resume();
			continue;
		}
		
		if(WSTOPSIG(status) == SIGTRAP) {
			// got trap, prepare to go into the savestate command interpreter
			if(inSyscall)
				// `kill(getpid(), SIGTRAP)` will stop the process while in a system call, during which
				// the process shouldn't be saved, so delay stopping until the syscall exits.
				shouldStop = true;
			else
				commands.doCommands();
			proc.tracer.resume();
		} else if(WSTOPSIG(status) == (SIGTRAP | 0x80)) {
			if(!inSyscall) {
				// entering syscall
				writeln("+ syscall: ", proc.tracer.getSyscall().to!string);
				inSyscall = true;
			} else {
				// exiting syscall
				inSyscall = false;
				if(shouldStop) {
					commands.doCommands();
					shouldStop = false;
				}
			}
			proc.tracer.resume();
		} else {
			proc.tracer.resume(WSTOPSIG(status));
		}
	}
	
	assert(false);
}
