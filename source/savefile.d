module savefile;

import std.string : toStringz, fromStringz;
import std.exception : enforce;
import std.range;
import std.algorithm;
import std.typecons;
import std.zlib;

import d2sqlite3;

import models;

bool isAutoCommit(ref Database db) {
	return sqlite3_get_autocommit(db.handle) != 0;
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
		auto stmt = db.prepare(`INSERT OR REPLACE INTO SaveStates VALUES (?, ?, ?);`);
		stmt.bind(1, state.id);
		stmt.bind(2, state.name);
		stmt.bind(3, (cast(ubyte*) (&state.registers))[0..Registers.sizeof]);
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
			if(map.contents)
				stmt.bind(11, cast(const(ubyte)[]) compress(map.contents, 9));
			else
				stmt.bind(11, null);
			
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
		
		ubyte[] registersBytes = results.front.peek!(ubyte[])(2);
		enforce(registersBytes.length == Registers.sizeof, "Saved registers do not match the current architecture.");
		
		SaveState state = {
			id: results.front.peek!ulong(0),
			name: results.front.peek!string(1),
			registers: *(cast(Registers*) registersBytes),
		};
		
		stmt = db.prepare(`SELECT * FROM MemoryMappings WHERE saveState = ?;`);
		stmt.bind(1, state.id.get);
		results = stmt.execute();
		foreach(row; results) {
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
			state.maps ~= map;
		}
		
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
		return Nullable!MemoryMap(map);
	}
	
	/**
	 * Writes a modified memory map to the savefile.
	 * TODO: Currently only updates the contents, and only works on anonymous
	 * maps.
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
}
