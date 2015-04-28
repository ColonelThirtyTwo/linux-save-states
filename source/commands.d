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

enum OPEN_SAVESTATES = q{
	auto saveStatesFile = SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();
	
	saveStatesFile.db.begin();
	scope(success) saveStatesFile.db.commit();
	scope(failure) if(!saveStatesFile.db.isAutoCommit) saveStatesFile.db.rollback();
};

// //////////////////////////////////////////////////////////////////////////

@("")
@(`Creates the savestate file.
Useful to create the file as a normal user, then run 'save' as root.`)
int cmd_create(string[] args) {
	mixin(ARG_HELP!cmd_create);
	mixin(ARG_NUM_REQUIRED!(cmd_create, 0));

	mixin(OPEN_SAVESTATES);

	return 0;
}

@("")
@("Lists all stored save states in chronological order.")
int cmd_list_states(string[] args) {
	mixin(ARG_HELP!cmd_list_states);
	mixin(ARG_NUM_REQUIRED!(cmd_list_states, 0));

	mixin(OPEN_SAVESTATES);

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
	
	mixin(OPEN_SAVESTATES);
	
	auto proc = new ProcessInfo(pid);
	scope(exit) proc.close();
	
	if(!proc.isStopped()) {
		stderr.writefln("PID %d is not stopped. Aborting.", pid);
		return 2;
	}
	
	saveStatesFile.writeState(proc.saveState(label));

	return 0;
}

@("<label>")
@("Shows info about a save state (memory maps, etc.)")
int cmd_show_state(string[] args) {
	mixin(ARG_HELP!cmd_show_state);
	mixin(ARG_NUM_REQUIRED!(cmd_show_state, 1));

	mixin(OPEN_SAVESTATES);
	
	auto state = saveStatesFile.loadState(args[0]);
	if(state.isNull) {
		stderr.writeln("No such state: "~args[0]);
		return 1;
	}
	
	writeln("Save state "~state.name~" (id: "~state.id.get.to!string~")");
	
	writeln("Memory Maps:");
	writeln("ID   | start addr     | end addr       | perm | name                                               | offset");
	writeln("-----|----------------|----------------|------|----------------------------------------------------|-------");
	
	foreach(ref map; state.maps) {
		writeln(
			only(
				leftJustify(map.id.to!string, 4),
				leftJustify("0x"~map.begin.to!string(16), 14),
				leftJustify("0x"~map.end.to!string(16), 14),
				only(
					(map.flags & MemoryMapFlags.READ) ? "r" : "-",
					(map.flags & MemoryMapFlags.WRITE) ? "w" : "-",
					(map.flags & MemoryMapFlags.EXEC) ? "x" : "-",
					(map.flags & MemoryMapFlags.PRIVATE) ? "p" : "s",
				).join,
				leftJustify(map.name, 50),
				map.offset.to!string,
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

	mixin(OPEN_SAVESTATES);

	auto map = saveStatesFile.getMap(id);
	if(map.isNull) {
		stderr.writeln("Map not found");
		return 1;
	}
	
	if(!map.contents) {
		stderr.writeln("No map contents to dump");
		return 1;
	}
	
	stdout.rawWrite(map.contents);
	
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

	mixin(OPEN_SAVESTATES);
	
	auto map = saveStatesFile.getMap(id);
	if(map.isNull) {
		stderr.writeln("Map not found");
		return 1;
	}
	assert(map.id == id);
	
	auto newContents = stdin.byChunk(4096).join();
	if(newContents.length != map.end - map.begin) {
		stderr.writeln("New contents must be the same length as the map size.");
		stderr.writefln("Old size: %s, new size: %s", newContents.length.to!string, (map.end-map.begin).to!string);
		return 1;
	}
	map.contents = newContents;
	
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
	
	mixin(OPEN_SAVESTATES);
	
	auto map = saveStatesFile.getMap(mapId);
	if(map.isNull) {
		stderr.writeln("Map not found");
		return 1;
	}
	
	if(!map.contents) {
		stderr.writeln("Map does not contain contents to load");
		return 1;
	}
	
	auto proc = new ProcessInfo(pid);
	scope(exit) proc.close();
	proc.writeMapContents(map);
	
	return 0;
}

@("<state label> <pid>")
@(`Loads a state into the specified process.`)
int cmd_load(string[] args) {
	mixin(ARG_HELP!cmd_load);
	mixin(ARG_NUM_REQUIRED!(cmd_load, 2));
	
	uint pid;
	try {
		pid = args[1].to!uint;
	} catch(ConvException ex) {
		stderr.writeln("Invalid ID");
		return 1;
	}

	mixin(OPEN_SAVESTATES);
	
	auto state = saveStatesFile.loadState(args[0]);
	if(state.isNull) {
		stderr.writeln("No such state: "~args[0]);
		return 2;
	}
	
	auto proc = new ProcessInfo(pid);
	scope(exit) proc.close();
	
	proc.loadState(state);
	
	return 0;
}
