module procinfo.memory;

import std.conv : to;
import std.typecons : BitFlags, Nullable, Tuple, tuple;
import std.variant : Algebraic;
import std.stdio : File, stderr;
import std.exception : enforce, errnoEnforce;
import std.regex;
import std.algorithm;
import std.range;
import std.c.linux.linux : pid_t;

import models;

/// Structure for reading a process' memory from /proc/[pid]/mem.
struct ProcMemory {
	immutable pid_t pid;
	private File mem;
	
	this(pid_t pid) {
		this.pid = pid;
		this.mem = File("/proc/"~to!string(pid)~"/mem", "r+b");
	}
	
	/// Reads memory maps from /proc/.
	/// The memory maps will not have their contents field set.
	private MemoryMap parseMapsLine(string line) {
		alias mapsLineRE = ctRegex!(
			`^([0-9a-fA-F]+)\-([0-9a-fA-F]+)\s+` // Memory range
			`([r\-][w\-][x\-][ps\-])\s+` // Permissions
			`([0-9a-fA-F]+)\s+` // Offset
			`[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\s+` // Device
			`[0-9]+\s+` // Inode
			`(.*)$` // Filepath (if any)
		);
		
		auto match = matchFirst(line, mapsLineRE);
		enforce(match, "Couldn't parse maps line: "~line);
		
		MemoryMap map;
		map.begin = match[1].to!ulong(16);
		map.end = match[2].to!ulong(16);
		
		auto perms = match[3];
		assert(perms.length == 4);
		if(perms[0] == 'r')
			map.flags |= MemoryMapFlags.READ;
		if(perms[1] == 'w')
			map.flags |= MemoryMapFlags.WRITE;
		if(perms[2] == 'x')
			map.flags |= MemoryMapFlags.EXEC;
		if(perms[3] == 'p')
			map.flags |= MemoryMapFlags.PRIVATE;
		
		map.name = match[5];
		map.offset = match[4].to!ulong(16);
		
		return map;
	}
	
	/// Loads the contents of the memory map.
	private void loadMapContents(ref MemoryMap mapDef) {
		mem.seek(mapDef.begin);
		auto buf = new ubyte[mapDef.end - mapDef.begin];
		mem.rawRead(buf);
		mapDef.contents = buf;
	}
	
	/// Returns a range of maps to save, with their contents loaded.
	/// The process should be stopped while this happens, to prevent race conditions.
	auto getMaps() {
		auto file = File("/proc/"~to!string(pid)~"/maps");
		return file.byLineCopy()
			.map!(line => this.parseMapsLine(line))
			.filter!(map =>
				(map.flags & (MemoryMapFlags.WRITE | MemoryMapFlags.PRIVATE)) ==
				(MemoryMapFlags.WRITE | MemoryMapFlags.PRIVATE)
			)
			.map!(delegate(MemoryMap map) {
				this.loadMapContents(map);
				return map;
			});
	}
	
	/**
	 * Writes the contents of an anonymous memory map to the process' memory.
	 *
	 * The process must have the memory mapped and writeable.
	 */
	void writeMapContents(in MemoryMap map)
	in {
		assert(map.contents);
	} body {
		mem.seek(map.begin);
		mem.rawWrite(map.contents);
	}
}

