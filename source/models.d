/// Data structures for info about a save state
module models;

import std.algorithm;
import std.range;
import std.typecons;
import std.exception;
import std.typetuple;

import bindings.ptrace : user_regs_struct, user_fpregs_struct;

private ubyte[] struct2blob(T)(auto ref const(T) t)
if(is(T == struct)) {
	return (cast(ubyte*) (&t))[0..T.sizeof].dup;
}

private T blob2struct(T)(const(ubyte)[] blob)
if(is(T == struct)) {
	assert(blob.length == T.sizeof);
	return *(cast(const(T)*) (blob.ptr));
}

// ReprTuple annotation for unique columns
struct ModelUnique(T) {
	T _val;
	alias _val this;
}

// ReprTuple annotation for foreign key columns
struct ForeignKey(PointsTo) {
	ulong id;
	alias id this;
}

/// Clock entry
struct Clock {
	///
	ulong sec, nsec;
}

/// Save state
final class SaveState {
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
	
	/// Window dimensions, or null if a window isn't opened.
	Nullable!(Tuple!(uint, uint)) windowSize;
	
	/// Returns the location of the program break (see `brk (2)`)
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
	
	alias ReprTuple = Tuple!(
		ModelUnique!string, "name",
		const(ubyte)[], "registers",
		ulong, "realtime_sec",
		ulong, "realtime_nsec",
		ulong, "monotonic_sec",
		ulong, "monotonic_nsec",
		Nullable!uint, "windowSize_x",
		Nullable!uint, "windowSize_y",
	);
	ReprTuple toTuple() {
		return ReprTuple(ModelUnique!string(name), registers.struct2blob, realtime.sec, realtime.nsec, monotonic.sec, monotonic.nsec,
			windowSize.isNull ? Nullable!uint() : Nullable!uint(windowSize.get[0]),
			windowSize.isNull ? Nullable!uint() : Nullable!uint(windowSize.get[1]),
		);
	}
	static typeof(this) fromTuple(ulong thisId, ReprTuple tup) {
		assert(tup.windowSize_x.isNull == tup.windowSize_y.isNull);
		
		auto state = new SaveState();
		with(state) {
			id = thisId;
			name = tup.name;
			registers = tup.registers.blob2struct!Registers,
			realtime.sec = tup.realtime_sec,
			realtime.nsec = tup.realtime_nsec,
			monotonic.sec = tup.monotonic_sec,
			monotonic.nsec = tup.monotonic_nsec,
			windowSize = tup.windowSize_x.isNull ? typeof(windowSize)() : typeof(windowSize)(tuple(tup.windowSize_x.get, tup.windowSize_y.get));
		}
		return state;
	}
	alias SubFields = TypeTuple!("maps", "files");
}

/// Memory map flags
enum MemoryMapFlags {
	READ = 1 << 0,
	WRITE = 1 << 1,
	EXEC = 1 << 2,
	PRIVATE = 1 << 3,
}

/// Memory map entry
final class MemoryMap {
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
	
	// serialization info:
	
	alias ReprTuple = Tuple!(
		ForeignKey!SaveState, "state",
		ulong, "begin",
		ulong, "end",
		uint, "flags",
		string, "name",
		ulong, "offset",
		const(ubyte)[], "contents",
	);
	
	ReprTuple toTuple(SaveState parent) {
		assert(parent.maps.canFind(this));
		return ReprTuple(ForeignKey!SaveState(parent.id), begin, end, flags, name, offset, contents);
	}
	static typeof(this) fromTuple(ulong thisId, ReprTuple tup) {
		auto map = new MemoryMap();
		with(map) {
			id = thisId;
			begin = tup.begin;
			end = tup.end;
			flags = tup.flags;
			name = tup.name,
			contents = tup.contents;
		}
		return map;
	}
}

/// File descriptor entry
final class FileDescriptor {
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
	
	alias ReprTuple = Tuple!(
		ForeignKey!SaveState, "state",
		int, "descriptor",
		string, "fileName",
		ulong, "pos",
		int, "flags"
	);
	
	ReprTuple toTuple(SaveState parent) {
		assert(parent.files.canFind(this));
		return ReprTuple(ForeignKey!SaveState(parent.id), descriptor, fileName, pos, flags);
	}
	static typeof(this) fromTuple(ulong thisId, ReprTuple tup) {
		auto map = new FileDescriptor();
		with(map) {
			id = thisId;
			descriptor = tup.descriptor;
			fileName = tup.fileName;
			pos = tup.pos;
			flags = tup.flags;
		}
		return map;
	}
}

/// Holds the contents of the (architecture dependent) registers.
struct Registers {
	user_regs_struct general;
	user_fpregs_struct floating;
}

/// Models to generate schemas for.
alias AllModels = TypeTuple!(SaveState, MemoryMap, FileDescriptor);
