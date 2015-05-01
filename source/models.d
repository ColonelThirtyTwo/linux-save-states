module models;

import std.typecons : Nullable;

public import procinfo.tracer : Registers;

/// Save state
struct SaveState {
	/// ID of state. Null if the state isn't saved.
	Nullable!(ulong, 0) id;
	
	/// Save state name, aka label
	string name;
	
	/// Saved memory maps
	MemoryMap[] maps;
	
	/// Saved registers
	Registers registers;
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
