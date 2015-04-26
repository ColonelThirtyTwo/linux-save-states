module commands;

import std.stdio;
import std.algorithm;
import std.range;
import std.conv : to, ConvException;
import std.format : format;
import std.string;
import std.zlib;
import std.traits;

import d2sqlite3;

import savestates;
import mapsparser;

enum PROGNAME = "linux-save-state";

template CommandName(alias cmd) {
	static if(isSomeFunction!cmd)
		enum cmdstr = __traits(identifier, cmd);
	else
		enum cmdstr = cmd;
	enum CommandName = cmdstr[4..$].replace("_", "-");
}

/// Gets help text for a command
template Help(alias cmd) {
	enum Help = "Usage: " ~ PROGNAME ~ " " ~ CommandName!cmd ~ " " ~
		__traits(getAttributes, cmd)[0] ~ "\n" ~
		__traits(getAttributes, cmd)[1];
}

/// Mixin: checks args for -h/--help, and prints USAGE if found.
template ARG_HELP(alias cmd) {
	enum ARG_HELP = q{
		if(args.canFind("--help") || args.canFind("-h")) {
			writeln(`%s`);
			return 0;
		}
	}.format(Help!cmd);
}

/// Mixin: Prints usage and errors out if args does not contain exactly n elements
template ARG_NUM_REQUIRED(alias cmd, uint n) {
	enum ARG_NUM_REQUIRED = q{
		if(args.length != %d) {
			stderr.writeln(`%s`);
			return 1;
		}
	}.format(n, Help!cmd);
}

// //////////////////////////////////////////////////////////////////////////

@("")
@(`Creates the savestate file.
Useful to create the file as a normal user, then run 'save' as root.`)
int cmd_create(string[] args) {
	mixin(ARG_HELP!cmd_create);
	mixin(ARG_NUM_REQUIRED!(cmd_create, 0));

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();

	return 0;
}

@("")
@("Lists all stored save states in chronological order.")
int cmd_list_states(string[] args) {
	mixin(ARG_HELP!cmd_list_states);
	mixin(ARG_NUM_REQUIRED!(cmd_list_states, 0));

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();

	foreach(label; saveStatesFile.listStates())
		writeln(label);
	return 0;
}

@("<label> <pid>")
@("Saves the state of a process.")
int cmd_save(string[] args) {
	mixin(ARG_HELP!cmd_save);
	mixin(ARG_NUM_REQUIRED!(cmd_save, 2));

	string label = args[0];
	uint pid;
	try {
		pid = to!uint(args[1]);
	} catch(ConvException ex) {
		stderr.writeln("Invalid ID");
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

@("<label>")
@("Shows info about a save state (memory maps, etc.)")
int cmd_show_state(string[] args) {
	mixin(ARG_HELP!cmd_show_state);
	mixin(ARG_NUM_REQUIRED!(cmd_show_state, 1));

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

@("<mapid> > contents.bin")
@("Writes the uncompressed contents of the specified map to stdio.")
int cmd_dump_map(string[] args) {
	mixin(ARG_HELP!cmd_dump_map);
	mixin(ARG_NUM_REQUIRED!(cmd_dump_map, 1));

	ulong id;
	try {
		id = args[0].to!ulong;
	} catch(ConvException ex) {
		stderr.writeln("Invalid ID");
		return 1;
	}

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();

	auto map = saveStatesFile.getMap(id);
	if(map.isNull) {
		stderr.writeln("Map not found");
		return 1;
	}
	
	auto target = map.target.peek!MemoryMapAnon;
	if(target is null) {
		stderr.writeln("Not an anonymous map");
		return 1;
	}
	
	stdout.rawWrite(target.uncompressedContents);
	
	return 0;
}

@("<mapid> < somefile.bin")
@(`Replaces the contents of the specified memory map with stdin.
The size of the new contents must match the size of the existing contents.`)
int cmd_replace_map(string[] args) {
	mixin(ARG_HELP!cmd_replace_map);
	mixin(ARG_NUM_REQUIRED!(cmd_replace_map, 1));

	ulong id;
	try {
		id = args[0].to!ulong;
	} catch(ConvException ex) {
		stderr.writeln("Invalid ID");
		return 1;
	}

	auto saveStatesFile = new SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();
	
	saveStatesFile.db.begin();
	scope(success) saveStatesFile.db.commit();
	scope(failure) if(!saveStatesFile.db.isAutoCommit) saveStatesFile.db.rollback();
	
	auto map = saveStatesFile.getMap(id);
	if(map.isNull) {
		stderr.writeln("Map not found");
		return 1;
	}
	assert(map.id == id);
	
	auto target = map.target.peek!MemoryMapAnon;
	if(target is null) {
		stderr.writeln("Not an anonymous map");
		return 1;
	}
	
	auto uncompressedContents = stdin.byChunk(4096).join();
	if(uncompressedContents.length != map.end - map.begin) {
		stderr.writeln("New contents must be the same length as the old contents");
		stderr.writefln("Old size: %s, new size: %s", uncompressedContents.length.to!string, (map.end-map.begin).to!string);
		return 1;
	}
	
	auto newContents = cast(const(ubyte)[]) compress(uncompressedContents, 9);
	target.contents = newContents;
	
	saveStatesFile.updateMap(map);
	
	return 0;
}

@("<mapid> <pid>")
@(`Loads the contents of the map specified by <mapid> into the memory of the process specified by <pid>.`)
int cmd_load_map(string[] args) {
	mixin(ARG_HELP!cmd_load_map);
	mixin(ARG_NUM_REQUIRED!(cmd_load_map, 2));
	
	ulong mapId;
	uint pid;
	try {
		mapId = args[0].to!ulong;
		pid = args[1].to!uint;
	} catch(ConvException ex) {
		stderr.writeln("Invalid ID");
		return 1;
	}
	
	auto saveStatesFile = new SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();
	
	auto map = saveStatesFile.getMap(mapId);
	if(map.isNull) {
		stderr.writeln("Map not found");
		return 1;
	}
	
	if(map.target.peek!MemoryMapAnon is null) {
		stderr.writeln("Not an anonymous map");
		return 1;
	}
	
	auto proc = new ProcessInfo(pid);
	scope(exit) proc.close();
	proc.writeMapContents(map);
	
	return 0;
}
