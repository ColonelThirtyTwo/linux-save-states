module models;

import std.algorithm;
import std.range;
import std.typecons : Nullable;

public import procinfo.tracer : Registers;

struct Clock {
	ulong sec, nsec;
}

/// Save state
struct SaveState {
	/// ID of state. Null if the state isn't saved.
	Nullable!(ulong, 0) id;
	
	/// Save state name, aka label
	string name;
	
	/// Saved registers
	Registers registers;
	
	/// Saved memory maps
	MemoryMap[] maps;
	
	/// Saved open files
	FileDescriptor[] files;
	
	/// Saved clocks
	Clock realtime;
	/// ditto
	Clock monotonic;
	
	/// Returns the location of the program break (see brk (2))
	ulong brk() @property const pure {
		auto heapMap = maps.find!(x => x.name == "[heap]");
		if(!heapMap.empty)
			return heapMap.front.end;
		
		// This is a bit of a hack. If there's no heap yet, assume it starts after the program's data segment
		// (which is the end of the first map that is writable and private)
		auto dataSegment = maps
			.filter!(x => x.flags == (MemoryMapFlags.READ | MemoryMapFlags.WRITE | MemoryMapFlags.PRIVATE))
			.minPos!((a,b) => a.begin < b.begin);
		assert(!dataSegment.empty);
		return dataSegment.front.end;
	}
}

/// Memory map flags
enum MemoryMapFlags {
	READ = 1 << 0,
	WRITE = 1 << 1,
	EXEC = 1 << 2,
	PRIVATE = 1 << 3,
}

/// Memory map entry
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

/// File descriptor entry
struct FileDescriptor {
	/// ID of the file. Null if the file isn't saved.
	Nullable!(ulong, 0) id;
	
	/// Descriptor ID
	int descriptor;
	
	/// Filename
	string fileName;
	
	/// File offset
	ulong pos;
	
	/// File open flags
	int flags;
}
