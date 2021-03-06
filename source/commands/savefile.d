/// Commands for inspecting saved states and other data.
module commands.savefile;

import std.stdio;
import std.algorithm;
import std.range;
import std.conv : to, ConvException;
import std.string;
import std.format;

import d2sqlite3;

import models;
import commands;
import savefile;
import procinfo;
import global;
import opengl.state;

private immutable string[] hexchars = iota(256).map!(byt => format("%02X", byt)).array.idup;

@("")
@("Lists all stored save states in chronological order.")
int cmd_list_states(string[] args) {
	mixin(ARG_HELP!cmd_list_states);
	mixin(ARG_NUM_REQUIRED!(cmd_list_states, 0));

	mixin(Transaction!saveFile);

	foreach(label; saveFile.list!(SaveState, "name")())
		writeln(label);
	return 0;
}


@("<label>")
@("Shows info about a save state (memory maps, etc.)")
int cmd_show_state(string[] args) {
	mixin(ARG_HELP!cmd_show_state);
	mixin(ARG_NUM_REQUIRED!(cmd_show_state, 1));
	
	mixin(Transaction!saveFile);
	
	auto state = saveFile.loadByField!(SaveState, "name")(args[0]);
	if(state is null) {
		stderr.writeln("No such state: "~args[0]);
		return 1;
	}
	
	writeln("Save state `"~state.name~"` (id: "~state.id.get.to!string~")");
	
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
	writeln("");
	
	writeln("Open Files:");
	writeln("Descriptor | Path                                                                        | position | flags");
	writeln("-----------|-----------------------------------------------------------------------------|----------|------");
	state.files.each!(file =>
		writeln(
			only(
				leftJustify(file.descriptor.to!string, 10),
				leftJustify(file.fileName, 75),
				leftJustify(file.pos.to!string, 8),
				leftJustify(file.flags.to!string, 6),
			).join(" | ")
		)
	);
	writeln("");
	
	writeln("Realtime clock: "~state.realtime.toString);
	writeln("Monotonic clock: "~state.monotonic.toString);
	writeln("");
	
	writeln("Window size: "~(state.windowSize.isNull ? "no window" : state.windowSize.get.toString));
	writeln("");
	
	auto glstate = GLState.deserialize(state.openGLState);
	writeln("OpenGL Buffers:");
	writeln("Client ID | Data Length | Hex");
	writeln("----------|-------------|---------");
	glstate.buffers.each!(buffer =>
		writeln(only(
			leftJustify(buffer.clientId.to!string, 9),
			leftJustify(buffer.contents.length.to!string, 11),
			buffer.contents.map!(byt => hexchars[byt]).take(50).join(" ") ~ (buffer.contents.length > 50 ? "..." : "")
		).join(" | "))
	);
	
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

	mixin(Transaction!saveFile);

	auto map = saveFile.loadByID!(MemoryMap)(id);
	if(map is null) {
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

/+

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
	
	mixin(Transaction!saveFile);
	
	auto map = saveFile.loadByID!(MemoryMap)(id);
	if(map is null) {
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
	
	saveFile.save(map);
	
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
	
	mixin(Transaction!saveFile);
	
	auto map = saveFile.getMap(mapId);
	if(map.isNull) {
		stderr.writeln("Map not found");
		return 1;
	}
	
	if(!map.contents) {
		stderr.writeln("Map does not contain contents to load");
		return 1;
	}
	
	auto proc = ProcMemory(pid);
	proc.writeMapContents(map);
	
	return 0;
}
+/
