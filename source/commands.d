module commands;

import std.stdio;
import std.algorithm;
import std.range;
import std.conv : to, ConvException;
import std.format : format;
import std.string;

import d2sqlite3;

import savestates;
import mapsparser;

/// Mixin: checks args for -h/--help, and prints USAGE if found.
enum ARG_HELP = q{
	if(args.canFind("--help") || args.canFind("-h")) {
		writeln(USAGE);
		return 0;
	}
};

/// Mixin: Prints USAGE and errors out if args does not contain exactly n elements
template ARG_NUM_REQUIRED(uint n) {
	enum ARG_NUM_REQUIRED = q{
		if(args.length != %d) {
			stderr.writeln(USAGE);
			return 1;
		}
	}.format(n);
}

int cmd_create(string[] args) {
	enum USAGE = `Usage: linux-save-state create
Creates the savestates file.`;
	mixin(ARG_HELP);
	mixin(ARG_NUM_REQUIRED!0);

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();

	return 0;
}

int cmd_list_states(string[] args) {
	enum USAGE = `Usage: linux-save-state list-states
Lists all stored save states in chronological order.`;
	mixin(ARG_HELP);
	mixin(ARG_NUM_REQUIRED!0);

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();

	foreach(label; saveStatesFile.listStates())
		writeln(label);
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
	scope(exit) saveStatesFile.close();
	auto proc = new ProcessInfo(pid);
	scope(exit) proc.close();
	
	if(!proc.isStopped()) {
		stderr.writefln("PID %d is not stopped. Aborting.", pid);
		return 2;
	}
	
	saveStatesFile.createState(label, proc.getMaps());

	return 0;
}

int cmd_show_state(string[] args) {
	enum USAGE = `Usage: linux-save-state show-state <label>
Shows info about a save state (memory maps, etc.)`;
	mixin(ARG_HELP);
	mixin(ARG_NUM_REQUIRED!1);

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();
	
	saveStatesFile.db.begin();
	scope(success) saveStatesFile.db.commit();
	scope(failure) if(saveStatesFile.db.isAutoCommit) saveStatesFile.db.rollback();

	// Find save state
	auto stmt = saveStatesFile.db.prepare(`SELECT rowid FROM SaveStates WHERE label = ?`);
	stmt.bind(1, args[0]);
	auto results = stmt.execute();
	if(results.empty) {
		stderr.writeln("No such label: "~args[0]);
		return 2;
	}

	writeln("Save state "~args[0]~" (id: "~results.front.peek!ulong(0).to!string~")");

	// Find maps
	stmt = saveStatesFile.db.prepare(`
		SELECT MemoryMappings.rowid, startPtr, endPtr, readMode, writeMode, execMode, privateMode, fileName, fileOffset
		FROM SaveStates
		INNER JOIN MemoryMappings ON SaveStates.rowid = MemoryMappings.saveState
		WHERE label = ?;
	`);
	stmt.bind(1, args[0]);
	results = stmt.execute();
	
	writeln("Memory Maps:");
	writeln("ID   | start addr     | end addr       | perm | name                                     | offset");
	writeln("-----|----------------|----------------|------|------------------------------------------|-------");
	
	foreach(row; results) {
		writeln(
			only(
				leftJustify(row.peek!ulong(0).to!string, 4),
				leftJustify("0x"~row.peek!ulong(1).to!string(16), 14),
				leftJustify("0x"~row.peek!ulong(2).to!string(16), 14),
				only(
					row.peek!bool(3) ? "r" : "-",
					row.peek!bool(4) ? "w" : "-",
					row.peek!bool(5) ? "x" : "-",
					row.peek!bool(6) ? "p" : "s",
				).join,
				leftJustify(row.columnType(7) != SqliteType.NULL ? row.peek!string(7) : "", 40),
				row.columnType(8) != SqliteType.NULL ? row.peek!ulong(8).to!string(16) : "n/a",
			).join(" | ")
		);
	}

	return 0;
}
