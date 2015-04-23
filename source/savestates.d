module savestates;

import std.string : toStringz, fromStringz;
import std.exception : enforce;
import std.range;
import etc.c.sqlite3;

import d2sqlite3;

import mapsparser;

/+
private struct Statement {
	sqlite3* db;
	sqlite3_stmt* stmt;
	alias stmt this;
	
	this(sqlite3* db, string query) {
		assert(query.length <= int.max);
		this.db = db;
		check(sqlite3_prepare_v2(db, query.ptr, cast(int)query.length, &stmt, null));
	}

	private void check(int code) {
		enforce(code == SQLITE_OK, sqlite3_errmsg(db).fromStringz());
	}
	
	bool step() {
		auto v = sqlite3_step(stmt);
		if(v == SQLITE_ROW)
			return true;
		else if(v == SQLITE_DONE)
			return false;
		else
			enforce(false, sqlite3_errmsg(db).fromStringz());
		assert(false);
	}

	void reset() {
		check(sqlite3_reset(stmt));
	}

	void bind(uint slot, typeof(null) val) {
		check(sqlite3_bind_null(stmt, slot));
	}

	void bind(uint slot, scope string val) {
		if(val is null) {
			check(sqlite3_bind_null(stmt, slot));
			return;
		}

		assert(val.length < int.max);
		check(sqlite3_bind_text(stmt, slot, val.ptr, cast(int)val.length, SQLITE_TRANSIENT));
	}

	void bind(uint slot, long val) {
		check(sqlite3_bind_int64(stmt, slot, val));
	}

	void bind(uint slot, scope const(ubyte)[] val) {
		if(val is null) {
			check(sqlite3_bind_null(stmt, slot));
			return;
		}

		assert(val.length < int.max);
		check(sqlite3_bind_blob(stmt, slot, val.ptr, cast(int)val.length, SQLITE_TRANSIENT));
	}

	void bind(uint slot, bool val) {
		check(sqlite3_bind_int(stmt, slot, val ? 1 : 0));
	}
	
	~this() {
		enforce(sqlite3_finalize(stmt) == SQLITE_OK, sqlite3_errmsg(db).fromStringz());
	}
}
+/

/**
 * Save state file reader and writer.
 * 
 * Save state files are SQLite 3 databases.
 */
final class SaveStatesFile {
	public Database db;
	
	this(string filepath) {
		db = Database(filepath);
		db.execute(import("schema.sql"));
	}

	/**
	 * Creates a new save state with the given label and memory maps.
	 */
	void createState(MemoryMapRange)(string label, MemoryMapRange memoryMaps)
	if(isInputRange!MemoryMapRange && is(ElementType!MemoryMapRange : const(MemoryMap))) {
		db.begin();
		scope(success) db.commit();
		scope(failure) if(!sqlite3_get_autocommit(db.handle)) db.rollback();
		
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
