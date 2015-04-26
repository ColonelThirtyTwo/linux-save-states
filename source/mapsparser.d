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
	BitFlags!MemoryMapFlags flags;
	
	/// Map contents. Either a reference to a file or a compressed copy of the map.
	Algebraic!(MemoryMapFile, MemoryMapAnon) target;
	
	invariant {
		assert(end >= begin);
	}
}

/// Memory mapped file.
struct MemoryMapFile {
	/// File path.
	string fileName;
	/// Offset in bytes.
	ulong fileOffset;
}

/// Anonymous memory map.
struct MemoryMapAnon {
	/// Name of the map, if any, as reported by /proc/pid/maps. Ex. [stack], [heap]
	string mapName;
	
	/// Memory contents, compressed with zlib
	const(ubyte)[] contents;
	
	/// Returns the decompressed memory contents
	const(ubyte)[] uncompressedContents() @property {
		// TODO: uncompress can't take a const array, but doesn't modify it, so we cast away const
		return cast(ubyte[]) uncompress(cast(ubyte[]) this.contents);
	}
	
	/// Compresses a byte buffer and assigns it to contents
	void uncompressedContents(const(ubyte)[] newContents) @property {
		this.contents = cast(const(ubyte)[]) compress(newContents, 9);
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
	
	/// Reads memory maps from /proc/ without loading them.
	/// Returns a tuple of a MemoryMap without a target, a string filename, and a ulong file offset.
	private Tuple!(MemoryMap, string, ulong) parseMapsLine(string line) {
		auto match = matchFirst(line, mapsLineRE);
		enforce(match, "Couldn't parse maps line: "~line);
		
		MemoryMap mapDef;
		mapDef.begin = match[1].to!ulong(16);
		mapDef.end = match[2].to!ulong(16);
		
		auto perms = match[3];
		assert(perms.length == 4);
		if(perms[0] == 'r')
			mapDef.flags |= MemoryMapFlags.READ;
		if(perms[1] == 'w')
			mapDef.flags |= MemoryMapFlags.WRITE;
		if(perms[2] == 'x')
			mapDef.flags |= MemoryMapFlags.EXEC;
		if(perms[3] == 'p')
			mapDef.flags |= MemoryMapFlags.PRIVATE;
		
		return tuple(mapDef, match[5], match[4].to!ulong(16));
		/*
		// TODO: private file maps should be copied rather than referred
		if(match[5] == "" || match[5] == "[stack]" || match[5] == "[heap]") {
			assert(match[4].to!ulong(16) == 0);

			mem.seek(mapDef.begin);
			auto buffer = new ubyte[mapDef.end - mapDef.begin];
			mem.rawRead(buffer);

			auto compressor = new Compress(6);
			auto compressedContents = cast(const(ubyte)[])  compressor.compress(buffer);
			compressedContents ~= cast(const(ubyte)[]) compressor.flush();
			
			mapDef.target = MemoryMapAnon(match[5], compressedContents);
			return Nullable!MemoryMap(mapDef);
		} else if(match[5][0] == '/') {
			mapDef.target = MemoryMapFile(match[5], match[4].to!ulong(16));
			return Nullable!MemoryMap(mapDef);
		} else {
			// TODO: handling [vdso] or other special maps
			return Nullable!MemoryMap();
		}
		*/
	}
	
	/// Loads a parsed MemoryMap. Returns false if the map cannot be loaded.
	private Nullable!MemoryMap loadMap(MemoryMap mapDef, string fileName, ulong fileOffset) {
		if(fileName == "" || fileName == "[stack]" || fileName == "[heap]") {
			mem.seek(mapDef.begin);
			auto buffer = new ubyte[mapDef.end - mapDef.begin];
			mem.rawRead(buffer);
			
			MemoryMapAnon target;
			target.mapName = fileName;
			target.uncompressedContents = buffer;
			mapDef.target = target;
			
		} else if(fileName[0] == '/') {
			mapDef.target = MemoryMapFile(fileName, fileOffset);
		} else {
			return Nullable!MemoryMap();
		}
		return Nullable!MemoryMap(mapDef);
	}

	bool isStopped() {
		auto stat = File("/proc/"~to!string(pid)~"/stat");
		auto line = stat.readln();
		auto match = line.matchFirst(statRE);
		assert(match);
		
		return match[1] == "T";
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
			.map!(tup => this.loadMap(tup.expand))
			.filter!(map => !map.isNull)
			.map!(map => map.get);
	}
	
	/**
	 * Writes the contents of an anonymous memory map to the process' memory.
	 *
	 * The process must have the memory mapped and writeable.
	 */
	void writeMapContents(MemoryMap map)
	in {
		assert(map.target.peek!MemoryMapAnon !is null);
	} body {
		mem.seek(map.begin);
		mem.rawWrite(map.target.peek!MemoryMapAnon.uncompressedContents);
	}

	/// Releases resources used by the process info.
	void close() {
		mem.close();
	}
}
