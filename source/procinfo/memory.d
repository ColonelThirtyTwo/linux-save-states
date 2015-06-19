/// Memory inspection
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
import procinfo : ProcInfo;
import procinfo.cmdpipe : Wrapper2AppCmd;
import procinfo.tracer : WaitEvent;

/// Reads memory maps from a file and returns a range.
auto readMemoryMaps(pid_t pid) {
	auto mapsFile = File("/proc/"~to!string(pid)~"/maps", "reb");
	auto memFile = File("/proc/"~to!string(pid)~"/mem", "r+eb");
	
	return mapsFile.byLineCopy()
		.map!(line => parseMapsLine(line))
		.filter!(map =>
			(map.flags & (MemoryMapFlags.WRITE | MemoryMapFlags.PRIVATE)) ==
			(MemoryMapFlags.WRITE | MemoryMapFlags.PRIVATE)
		)
		.array()
		.mapLoaderRange(memFile)
	;
}

/// Writes the contents of a range of memory maps to a process.
/// The process needs to have memory maps set up where the maps are written to.
void writeMemoryMaps(Range)(pid_t pid, Range maps)
if(isInputRange!Range && is(ElementType!Range : const(MemoryMap))) {
	auto memFile = File("/proc/"~to!string(pid)~"/mem", "r+eb");
	
	foreach(const map; maps) {
		assert(map.contents.ptr != null);
		memFile.seek(map.begin);
		memFile.rawWrite(map.contents);
	}
}

/// Sets the program break
void setBrk()(auto ref ProcInfo proc, ulong addr) {
	assert(addr <= size_t.max);
	
	proc.write(
		Wrapper2AppCmd.CMD_SETHEAP,
		cast(void*) addr
	);
}

// ///////////////////////////////////////////////////////////////////////

private struct MapLoaderRange(T)
if(isInputRange!T && is(ElementType!T : MemoryMap)) {
	private T subrange;
	private File memFile;
	MemoryMap front;
	
	this(T subrange, File memFile) {
		this.memFile = memFile;
		this.subrange = subrange;
		
		setFront();
	}
	private void setFront() {
		if(subrange.empty)
			memFile.detach();
		else
			front = loadMapContents(memFile, subrange.front);
	}
	
	auto empty() @property {
		return subrange.empty;
	}
	
	void popFront() {
		subrange.popFront();
		setFront();
	}
}

private auto mapLoaderRange(T)(T range, File memFile) {
	return MapLoaderRange!T(range, memFile);
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
private MemoryMap loadMapContents(File memFile, MemoryMap map) {
	memFile.seek(map.begin);
	auto buf = new ubyte[map.end - map.begin];
	memFile.rawRead(buf);
	map.contents = buf;
	return map;
}
