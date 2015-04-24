module savestates;

import std.string : toStringz, fromStringz;
import std.exception : enforce;
import std.range;
import etc.c.sqlite3;

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

		stmt = db.prepare(`INSERT INTO MemoryMappings
			(saveState, startPtr, endPtr, readMode, writeMode, execMode, privateMode, fileName, fileOffset, contents) VALUES
			(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);`);
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

			if(mapEntry.target.peek!MemoryMapFile !is null) {
				auto mapContents = mapEntry.target.peek!MemoryMapFile;
				stmt.bind(8, mapContents.fileName);
				assert(mapContents.fileOffset <= long.max);
				stmt.bind(9, cast(long) mapContents.fileOffset);
				stmt.bind(10, null);
			} else {
				auto mapContents = mapEntry.target.peek!MemoryMapAnon;
				stmt.bind(8, mapContents.mapName);
				stmt.bind(9, null);
				stmt.bind(10, mapContents.contents);
			}

			stmt.execute();
			stmt.reset();
		}
	}

	/// Returns a range of all savestate labels in chronological order.
	auto listStates() {
		auto stmt = db.prepare(`SELECT label FROM SaveStates ORDER BY rowid;`);
		return stmt.execute().map!(x => x[0]);
	}

	/**
	 * Closes the save states file.
	 */
	void close() {
		db.close();
	}
}
