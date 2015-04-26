module mapsparser;

import std.conv : to;
import std.typecons : BitFlags, Nullable, Tuple, tuple;
import std.variant : Algebraic;
import std.stdio : File, stderr;
import std.exception : enforce;
import std.regex;
import std.algorithm;
import std.range;
import std.zlib;

/// Memory map flags
enum MemoryMapFlags {
	READ = 1 << 0,
	WRITE = 1 << 1,
	EXEC = 1 << 2,
	PRIVATE = 1 << 3,
}

/// Defines a memory map.
struct MemoryMap {
	/// ID of the memory map. Null if the map isn't saved.
	Nullable!(ulong, 0) id;
	
	/// Start address
	ulong begin;
	/// End address
	ulong end;
	/// Permissions
	uint flags;
	//BitFlags!MemoryMapFlags flags;
	
	/// Memory map name. It may be a file path, or a label like [heap], [stack].
	string name;
	
	/// File offset of the memory map. Meaningless for an anonymous map.
	ulong offset;
	
	/// For private or anonymous maps, the map contents. If the length is zero, the contents were not stored.
	const(ubyte)[] contents;
	
	invariant {
		assert(end >= begin);
		assert(!contents || contents.length == (end - begin));
	}
}

// //////////////////////////////////////////////////////////////////////////////////////////

private {
	alias mapsLineRE = ctRegex!(
		`^([0-9a-fA-F]+)\-([0-9a-fA-F]+)\s+` // Memory range
		`([r\-][w\-][x\-][ps\-])\s+` // Permissions
		`([0-9a-fA-F]+)\s+` // Offset
		`[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\s+` // Device
		`[0-9]+\s+` // Inode
		`(.*)$` // Filepath (if any)
	);

	alias statRE = ctRegex!`^[^\s]+ [^\s]+ (.)`;
}

/**
 * Class for getting process information.
 */
final class ProcessInfo {
	private {
		File mem;
		uint pid;
	}

	this(uint pid)
	in {
		assert(pid != 0);
	} body {
		mem = File("/proc/"~to!string(pid)~"/mem", "r+b");
		this.pid = pid;
	}
	
	/// Reads memory maps from /proc/.
	/// The memory maps will not have their contents field set.
	private MemoryMap parseMapsLine(string line) {
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
	
	private void loadMapContents(ref MemoryMap mapDef) {
		mem.seek(mapDef.begin);
		auto buf = new ubyte[mapDef.end - mapDef.begin];
		mem.rawRead(buf);
		mapDef.contents = buf;
	}
	
	/**
	 * Returns a range of MemoryMaps read from the process.
	 * 
	 * The ProcessInfo must not be closed when reading from the range.
	 */
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
	
	/// Checks if the process is stopped.
	bool isStopped() {
		auto stat = File("/proc/"~to!string(pid)~"/stat");
		auto line = stat.readln();
		auto match = line.matchFirst(statRE);
		assert(match);
		
		return match[1] == "T";
	}
	
	/**
	 * Writes the contents of an anonymous memory map to the process' memory.
	 *
	 * The process must have the memory mapped and writeable.
	 */
	void writeMapContents(MemoryMap map)
	in {
		assert(map.contents);
	} body {
		mem.seek(map.begin);
		mem.rawWrite(map.contents);
	}

	/// Releases resources used by the process info.
	void close() {
		mem.close();
	}
}
