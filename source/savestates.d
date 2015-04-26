module savestates;

import std.string : toStringz, fromStringz;
import std.exception : enforce;
import std.range;
import std.algorithm;
import std.typecons;
import std.zlib;

import d2sqlite3;

import mapsparser;

bool isAutoCommit(ref Database db) {
	return sqlite3_get_autocommit(db.handle) != 0;
}

/**
 * Save state file reader and writer.
 * 
 * Save state files are SQLite 3 databases.
 */
final class SaveStatesFile {
	public Database db;
	
	this(string filepath) {
		db = Database(filepath);
		db.run(import("schema.sql"));
	}

	/**
	 * Creates a new save state with the given label and memory maps.
	 */
	void createState(MemoryMapRange)(string label, MemoryMapRange memoryMaps)
	if(isInputRange!MemoryMapRange && is(ElementType!MemoryMapRange : const(MemoryMap))) {
		db.begin();
		scope(success) db.commit();
		scope(failure) if(!db.isAutoCommit) db.rollback();
		
		assert(label.length <= int.max);
		auto stmt = db.prepare(`INSERT INTO SaveStates(label) VALUES (?);`);
		stmt.bind(1, label);
		stmt.execute();
		
		const saveStateID = db.lastInsertRowid;
		
		stmt = db.prepare(`
			INSERT INTO MemoryMappings
			(saveState, startPtr, endPtr, readMode, writeMode, execMode, privateMode, fileName, fileOffset, contents) VALUES
			(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
		`);
		
		foreach(MemoryMap mapEntry; memoryMaps) {
			// TODO: SQLite doesn't support unsigned 64-bit numbers.
			assert(mapEntry.begin <= long.max);
			assert(mapEntry.end <= long.max);
			
			stmt.bind(1, saveStateID);
			stmt.bind(2, mapEntry.begin);
			stmt.bind(3, mapEntry.end);
			stmt.bind(4, !!(mapEntry.flags & MemoryMapFlags.READ));
			stmt.bind(5, !!(mapEntry.flags & MemoryMapFlags.WRITE));
			stmt.bind(6, !!(mapEntry.flags & MemoryMapFlags.EXEC));
			stmt.bind(7, !!(mapEntry.flags & MemoryMapFlags.PRIVATE));
			stmt.bind(8, mapEntry.name);
			stmt.bind(9, mapEntry.offset);
			if(mapEntry.contents)
				stmt.bind(10, cast(const(ubyte)[]) compress(mapEntry.contents, 9));
			else
				stmt.bind(10, null);
			
			stmt.execute();
			stmt.reset();
		}
	}

	/// Returns a range of all savestate labels in chronological order.
	auto listStates() {
		auto stmt = db.prepare(`SELECT label FROM SaveStates ORDER BY rowid;`);
		return stmt.execute().map!(x => x[0]);
	}
	
	/// Returns a range of MemoryMaps for the specified save state
	auto getMaps(string saveStateLabel, bool withContents=true) {
		auto stmt = db.prepare(`
			SELECT MemoryMappings.rowid, startPtr, endPtr, readMode, writeMode, execMode, privateMode, fileName, fileOffset
			` ~ (withContents ? `, contents ` : ``) ~ `
			FROM SaveStates
			INNER JOIN MemoryMappings ON SaveStates.rowid = MemoryMappings.saveState
			WHERE label = ?;
		`);
		stmt.bind(1, saveStateLabel);
		
		return stmt.execute()
			.map!(delegate(row) {
				MemoryMap m = {
					id: row.peek!ulong(0),
					begin: row.peek!ulong(1),
					end: row.peek!ulong(2),
					flags:
						(row.peek!bool(3) ? MemoryMapFlags.READ : 0) |
						(row.peek!bool(4) ? MemoryMapFlags.WRITE : 0) |
						(row.peek!bool(5) ? MemoryMapFlags.EXEC : 0) |
						(row.peek!bool(6) ? MemoryMapFlags.PRIVATE : 0),
					name: row.peek!string(7),
					offset: row.peek!ulong(8),
					contents: withContents ? cast(const(ubyte)[]) uncompress(
						row.peek!(ubyte[])(9),
						row.peek!ulong(2) - row.peek!ulong(1)
					) : null,
				};
				return m;
			});
	}

	Nullable!MemoryMap getMap(ulong id) {
		auto stmt = db.prepare(`SELECT * FROM MemoryMappings WHERE rowid = ?;`);
		stmt.bind(1, id);
		auto results = stmt.execute();
		
		if(results.empty)
			return Nullable!MemoryMap();
		auto row = results.front;
		
		MemoryMap map;
		map.id = id;
		map.begin = row.peek!ulong(1);
		map.end = row.peek!ulong(2);
		if(row.peek!bool(3))
			map.flags |= MemoryMapFlags.READ;
		if(row.peek!bool(4))
			map.flags |= MemoryMapFlags.WRITE;
		if(row.peek!bool(5))
			map.flags |= MemoryMapFlags.EXEC;
		if(row.peek!bool(6))
			map.flags |= MemoryMapFlags.PRIVATE;
		
		map.name = row.peek!string(7);
		map.offset = row.peek!ulong(8);
		map.contents = cast(const(ubyte)[]) uncompress(row.peek!(ubyte[])(9), map.end - map.begin);
		
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

	/**
	 * Closes the save states file.
	 */
	void close() {
		db.close();
	}
}
