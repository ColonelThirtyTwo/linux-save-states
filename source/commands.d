module commands;

import std.stdio;
import std.algorithm : canFind;
import std.conv : to, ConvException;
import std.format : format;

import savestates;
import mapsparser;

enum ARG_HELP = q{
	if(args.canFind("--help") || args.canFind("-h")) {
		writeln(USAGE);
		return 0;
	}
};

template ARG_NUM_REQUIRED(uint n) {
	enum ARG_NUM_REQUIRED = q{
		if(args.length != %d) {
			stderr.writeln(USAGE);
			return 1;
		}
	}.format(n);
}

int cmd_list_states(string[] args) {
	enum USAGE = `Usage: linux-save-state list-states
Lists all stored save states in chronological order.`;
	mixin(ARG_HELP);
	mixin(ARG_NUM_REQUIRED!0);

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	foreach(label; saveStatesFile.listStates())
		writeln(label);
	saveStatesFile.close();
	return 0;
}

int cmd_save(string[] args) {
	enum USAGE = `Usage: linux-save-state save <label> <pid>`;
	mixin(ARG_HELP);
	mixin(ARG_NUM_REQUIRED!2);

	string label = args[0];
	uint pid;
	try {
		pid = to!uint(args[1]);
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
