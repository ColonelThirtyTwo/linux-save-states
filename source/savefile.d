/// Opening, saving, and serializing save states.
module savefile;

import std.string : toStringz, fromStringz;
import std.exception : enforce;
import std.range;
import std.algorithm;
import std.typecons;
import std.zlib;

import d2sqlite3;

import models;

/// Returns true if the database is in autocommit mode
bool isAutoCommit(ref Database db) {
	return sqlite3_get_autocommit(db.handle) != 0;
}

/// Mixin: Begins and commits/rollbacks transaction on a save file.
template Transaction(alias savefile) {
	enum Transaction = q{
		FILE.db.begin();
		scope(success) FILE.db.commit();
		scope(failure) if(!FILE.db.isAutoCommit) FILE.db.rollback();
	}.replace("FILE", __traits(identifier, savefile));
}

/**
 * Save state file reader and writer.
 * 
 * Save state files are SQLite 3 databases.
 */
struct SaveStatesFile {
	public Database db;
	
	this(string filepath) {
		db = Database(filepath);
		db.run(import("schema.sql"));
	}
	
	/**
	 * Updates or creates a save state and associated objects.
	 * You probably want to run this in a transaction.
	 */ 
	void writeState()(auto ref SaveState state) {
		auto stmt = db.prepare(`INSERT OR REPLACE INTO SaveStates VALUES (?,?,?,?,?,?,?,?,?);`);
		stmt.bind(1, state.id);
		stmt.bind(2, state.name);
		stmt.bind(3, (cast(ubyte*) (&state.registers))[0..Registers.sizeof]);
		stmt.bind(4, state.realtime.sec);
		stmt.bind(5, state.realtime.nsec);
		stmt.bind(6, state.monotonic.sec);
		stmt.bind(7, state.monotonic.nsec);
		if(state.windowSize.isNull) {
			stmt.bind(8, null);
			stmt.bind(9, null);
		} else {
			stmt.bind(8, state.windowSize[0]);
			stmt.bind(9, state.windowSize[1]);
		}
		stmt.execute();
		
		state.id = db.lastInsertRowid;
		
		stmt = db.prepare(`DELETE FROM MemoryMappings WHERE saveState = ?;`);
		stmt.bind(1, state.id);
		stmt.execute();
		
		stmt = db.prepare(`INSERT INTO MemoryMappings VALUES (?,?,?,?,?,?,?,?,?,?,?);`);
		foreach(ref map; state.maps) {
			stmt.bind(1, map.id);
			stmt.bind(2, state.id.get);
			stmt.bind(3, map.begin);
			stmt.bind(4, map.end);
			stmt.bind(5, !!(map.flags & MemoryMapFlags.READ));
			stmt.bind(6, !!(map.flags & MemoryMapFlags.WRITE));
			stmt.bind(7, !!(map.flags & MemoryMapFlags.EXEC));
			stmt.bind(8, !!(map.flags & MemoryMapFlags.PRIVATE));
			stmt.bind(9, map.name);
			stmt.bind(10, map.offset);
			if(map.contents.ptr != null)
				stmt.bind(11, cast(const(ubyte)[]) compress(map.contents, 9));
			else
				stmt.bind(11, null);
			
			stmt.execute();
			stmt.reset();
		}
		
		stmt = db.prepare(`DELETE FROM Files WHERE saveState = ?;`);
		stmt.bind(1, state.id);
		stmt.execute();
		
		stmt = db.prepare(`INSERT INTO Files VALUES (?, ?, ?, ?, ?, ?);`);
		foreach(ref file; state.files) {
			stmt.bind(1, file.id);
			stmt.bind(2, state.id.get);
			stmt.bind(3, file.descriptor);
			stmt.bind(4, file.fileName);
			stmt.bind(5, file.pos);
			stmt.bind(6, file.flags);
			
			stmt.execute();
			stmt.reset();
		}
	}
	
	/// Returns a range of state labels in chronological order.
	auto listStates() {
		auto stmt = db.prepare(`SELECT label FROM SaveStates ORDER BY rowid;`);
		return stmt.execute().map!(x => x[0]);
	}
	
	/// Loads a state by its name. Returns null if not found.
	Nullable!SaveState loadState(string name) {
		auto stmt = db.prepare(`SELECT * FROM SaveStates WHERE label = ?;`);
		stmt.bind(1, name);
		auto results = stmt.execute();
		
		if(results.empty)
			return Nullable!SaveState();
		
		auto result = results.front;
		
		ubyte[] registersBytes = result.peek!(ubyte[])(2);
		enforce(registersBytes.length == Registers.sizeof, "Saved registers do not match the current architecture.");
		
		SaveState state = {
			id: result.peek!ulong(0),
			name: result.peek!string(1),
			registers: *(cast(Registers*) registersBytes),
			realtime: {sec: result.peek!ulong(3), nsec: result.peek!ulong(4)},
			monotonic: {sec: result.peek!ulong(5), nsec: result.peek!ulong(6)},
			
			windowSize: result.columnType(7) == SqliteType.NULL ?
				typeof(SaveState.windowSize)() :
				typeof(SaveState.windowSize)(tuple(result.peek!uint(7), result.peek!uint(8)))
		};
		
		stmt = db.prepare(`SELECT * FROM MemoryMappings WHERE saveState = ?;`);
		stmt.bind(1, state.id.get);
		state.maps = stmt.execute().map!(x => readMemoryMap(x)).array();
		
		stmt = db.prepare(`SELECT * FROM Files WHERE saveState = ?;`);
		stmt.bind(1, state.id.get);
		state.files = stmt.execute().map!(x => readFileDescriptor(x)).array();
		
		return Nullable!SaveState(state);
	}
	
	/// Loads one map from the database
	Nullable!MemoryMap getMap(ulong id) {
		auto stmt = db.prepare(`SELECT * FROM MemoryMappings WHERE rowid = ?;`);
		stmt.bind(1, id);
		auto results = stmt.execute();
		
		if(results.empty)
			return Nullable!MemoryMap();
		auto row = results.front;
		return Nullable!MemoryMap(readMemoryMap(row));
	}
	
	/**
	 * Writes a modified memory map to the savefile.
	 * TODO: Currently only updates the contents, and only works on anonymous maps.
	 */
	void updateMap(const ref MemoryMap map)
	in {
		assert(!map.id.isNull);
	} body {
		auto stmt = db.prepare(`UPDATE MemoryMappings SET contents = ? WHERE rowid = ?;`);
		stmt.bind(1, cast(const(ubyte)[]) compress(map.contents, 9));
		stmt.bind(2, map.id.get);
		stmt.execute();
		assert(db.changes == 1);
	}
	
	/// Sets a value in the Settings table, which is a simple key/value store.
	void opIndexAssign(T)(T value, string name) {
		auto stmt = db.prepare(`INSERT OR REPLACE INTO Settings VALUES (?,?);`);
		stmt.bind(1, name);
		stmt.bind(2, value);
		stmt.execute();
	}
	
	/// Gets a value in the Settings table, which is a simple key/value store.
	ColumnData opIndex(string name) {
		auto stmt = db.prepare(`SELECT value FROM Settings WHERE name = ?;`);
		stmt.bind(1, name);
		auto results = stmt.execute();
		if(results.empty)
			return ColumnData.init;
		return results.front.front;
	}
	
	private MemoryMap readMemoryMap(Row row) {
		MemoryMap map = {
			id: row.peek!ulong(0),
			begin: row.peek!ulong(2),
			end: row.peek!ulong(3),
			flags:
				(row.peek!bool(4) ? MemoryMapFlags.READ : 0) |
				(row.peek!bool(5) ? MemoryMapFlags.WRITE : 0) |
				(row.peek!bool(6) ? MemoryMapFlags.EXEC : 0) |
				(row.peek!bool(7) ? MemoryMapFlags.PRIVATE : 0),
			name: row.peek!string(8),
			offset: row.peek!ulong(9),
			contents: cast(const(ubyte)[]) uncompress(
				row.peek!(ubyte[])(10),
				row.peek!ulong(3) - row.peek!ulong(2)
			),
		};
		return map;
	}
	
	private FileDescriptor readFileDescriptor(Row row) {
		FileDescriptor file = {
			id: row.peek!ulong(0),
			descriptor: row.peek!int(2),
			fileName: row.peek!string(3),
			pos: row.peek!ulong(4),
			flags: row.peek!int(5),
		};
		return file;
	}
}
