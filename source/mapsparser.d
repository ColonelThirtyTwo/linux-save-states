module mapsparser;

import std.conv : to;
import std.typecons : BitFlags, Nullable;
import std.variant : Algebraic;
import std.stdio : File, stderr;
import std.exception : enforce;
import std.regex;
import std.algorithm : map, filter;
import std.range : join;
import std.zlib : Compress;

/// Memory map flags
enum MemoryMapFlags {
	READ = 1 << 0,
	WRITE = 1 << 1,
	EXEC = 1 << 2,
	PRIVATE = 1 << 3,
}

/// Defines a memory map.
struct MemoryMap {
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
		assert(target.hasValue);
		if(target.peek!MemoryMapAnon !is null)
			assert(target.peek!MemoryMapAnon.contents.length == end - begin);
	}
}

/// Memory mapped file.
struct MemoryMapFile {
	string fileName;
	ulong fileOffset;
}

/// Anonymous memory map.
struct MemoryMapAnon {
	/// Memory contents, compressed with zlib.
	const(ubyte)[] contents;
}

// //////////////////////////////////////////////////////////////////////////////////////////

private alias mapsLineRE = ctRegex!(
	`^([0-9a-fA-F]+)\-([0-9a-fA-F]+)\s+` // Memory range
	`([r\-][w\-][x\-][ps\-])\s+` // Permissions
	`([0-9a-fA-F]+)\s+` // Offset
	`[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\s+` // Device
	`[0-9]+\s+` // Inode
	`(.*)$` // Filepath (if any)
);

final class ProcessInfo {
	private {
		File mem;
		uint pid;
	}

	this(uint pid)
	in {
		assert(pid != 0);
	} body {
		mem = File("/proc/"~to!string(pid)~"/mem");
		this.pid = pid;
	}

	private Nullable!MemoryMap parseMapsLine(string line) {
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
		
		// TODO: private file maps should be copied rather than referred
		if(match[5] == "" || match[5] == "[stack]" || match[5] == "[heap]") {
			assert(match[4].to!ulong(16) == 0);

			mem.seek(mapDef.begin);
			auto buffer = new ubyte[mapDef.end - mapDef.begin];
			mem.rawRead(buffer);

			auto compressor = new Compress(6);
			auto compressedContents = cast(const(ubyte)[])  compressor.compress(buffer);
			compressedContents ~= cast(const(ubyte)[]) compressor.flush();
			
			mapDef.target = MemoryMapAnon(compressedContents);
			return Nullable!MemoryMap(mapDef);
		} else if(match[5][0] == '/') {
			mapDef.target = MemoryMapFile(match[5], match[4].to!ulong(16));
			return Nullable!MemoryMap(mapDef);
		} else {
			// TODO: handling [vdso] or other special maps
			return Nullable!MemoryMap();
		}
	}

	auto getMaps() {
		auto file = File("/proc/"~to!string(pid)~"/maps");
		return file.byLineCopy()
			.map!(x => this.parseMapsLine(x))
			.filter!(a => !a.isNull)
			.map!(a => a.get);
	}

	void close() {
		mem.close();
	}
}

/+
/// Reads and returns a range of all the maps of a process.
auto readMaps(uint pid)
in {
	assert(pid != 0);
} body {
	immutable pidStr = to!string(pid);
	
	auto readMapsLine = delegate(string line) {
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
		
		// TODO: private file maps should be copied rather than referred
		if(match[5] == "" || match[5] == "[stack]" || match[5] == "[heap]") {
			assert(match[4].to!ulong(16) == 0);
			
			auto mapFile = File("/proc/"~pidStr~"/map_files/"~match[1]~"-"~match[2]);
			auto compressor = new Compress(6);
			auto compressedContents = mapFile
				.byChunk(4096)
				.map!(a => cast(const(ubyte)[]) compressor.compress(a))
				.join();
			compressedContents ~= cast(const(ubyte)[]) compressor.flush();
			
			mapDef.target = MemoryMapAnon(compressedContents);
			return Nullable!MemoryMap(mapDef);
		} else if(match[5][0] == '/') {
			mapDef.target = MemoryMapFile(match[5], match[4].to!ulong(16));
			return Nullable!MemoryMap(mapDef);
		} else {
			// TODO: handling [vdso] or other special maps
			return Nullable!MemoryMap();
		}
	};
	
	auto file = File("/proc/"~pidStr~"/maps");
	return file.byLineCopy()
		.map!readMapsLine
		.filter!(a => !a.isNull)
		.map!(a => a.get);
}
+/