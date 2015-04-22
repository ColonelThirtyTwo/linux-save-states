
import std.stdio;
import std.exception : enforce, errnoEnforce;
//import std.c.linux;
import etc.c.sqlite3;
import core.sys.posix.unistd;
import std.conv : to, ConvException;
import std.algorithm : canFind;

import savestates;
import mapsparser;

enum ARG_HELP = q{
	if(args.canFind("--help") || args.canFind("-h")) {
		writeln(USAGE);
		return 0;
	}
};

int main(string[] args) {
	enum USAGE = `Usage: linux-save-state <command>
Command is one of:
* list-states
* save
`;
	if(args.length < 2) {
		stderr.writeln(USAGE);
		return 1;
	}

	if(args[1] == "--help" || args[1] == "-h" || args[1] == "help") {
		writeln(USAGE);
		return 0;
	}

	switch(args[1]) {
		case "save":
			return cmd_save(args[2..$]);
		case "list-states":
			return cmd_listStates(args[2..$]);
		default:
			stderr.writeln(USAGE);
			stderr.writeln("No such command: "~args[1]);
			return 1;
	}
}

int cmd_listStates(string[] args) {
	enum USAGE = `Usage: linux-save-state list-states
Lists all stored save states in chronological order.`;
	mixin(ARG_HELP);

	if(args.length != 0) {
		stderr.writeln(USAGE);
		return 1;
	}

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	foreach(label; saveStatesFile.listStates())
		writeln(label);
	saveStatesFile.close();
	return 0;
}

int cmd_save(string[] args) {
	enum USAGE = `Usage: linux-save-state save <label> <pid>`;
	mixin(ARG_HELP);

	if(args.length != 2) {
		stderr.writeln(USAGE);
		return 1;
	}

	string label = args[1];
	uint pid;
	try {
		pid = to!uint(args[2]);
	} catch(ConvException ex) {
		stderr.writeln(USAGE);
		return 1;
	}

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	auto proc = new ProcessInfo(pid);
	
	if(!proc.isStopped()) {
		stderr.writefln("PID %d is not stopped. Aborting.", pid);
		return 2;
	}
	
	saveStatesFile.createState(label, proc.getMaps());
	proc.close();
	saveStatesFile.close();
	return 0;
}
