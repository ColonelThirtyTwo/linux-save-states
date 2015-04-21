
import std.stdio;
import std.exception : enforce, errnoEnforce;
//import std.c.linux;
import etc.c.sqlite3;
import core.sys.posix.unistd;
import std.conv : to, ConvException;
import std.algorithm : canFind;

import savestates;
import mapsparser;

enum USAGE = `Usage: linux-save-state label pid`;

int main(string[] args) {
	uint pid;
	string label;

	if(args[1..$].canFind("--help") || args[1..$].canFind("-h")) {
		writeln(USAGE);
		return 0;
	}

	if(args.length < 3) {
		stderr.writeln(USAGE);
		return 1;
	}

	label = args[1];
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


	/*
	int[2] pipeFds;
	errnoEnforce(pipe(pipeFds.ptr) == 0);
	
	File readPipe, writePipe;
	readPipe.fdopen(pipeFds[0], "rb");
	writePipe.fdopen(pipeFds[1], "wb");
	
	while(true) {
		auto cmd = readPipe.readln();
		
		
	}*/
	proc.close();
	saveStatesFile.close();
	return 0;
}
