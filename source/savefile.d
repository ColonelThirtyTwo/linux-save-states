/// Opening, saving, and serializing save states.
module savefile;

import std.string : toStringz, fromStringz;
import std.exception : enforce;
import std.range;
import std.algorithm;
import std.typecons : Nullable, tuple, Tuple;
import std.zlib;
import std.traits;
import std.typetuple;

import d2sqlite3;

import models;

/// Returns true if the database is in autocommit mode
bool isAutoCommit(ref Database db) {
	return sqlite3_get_autocommit(db.handle) != 0;
}

/// Mixin that begins and commits/rollbacks transaction on a save file.
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
		db.run(Schema);
	}
	
	private T loadFromRow(T, Args...)(Row row, Args extra) {
		T.ReprTuple tup;
		foreach(i, ref item; tup.expand) {
			static if(is(typeof(item) : ForeignKey!Typ, Typ))
				item = ForeignKey!Typ(row.peek!ulong(i+1));
			else static if(is(typeof(item) : ModelUnique!Typ, Typ))
				item = ModelUnique!Typ(row.peek!Typ(i+1));
			else
				item = row.peek!(typeof(item))(i+1);
		}
		auto obj = T.fromTuple(row.peek!(ulong)(0), tup, extra);
		loadSubObjects(obj);
		return obj;
	}
	
	private void loadSubObjects(T)(T obj)
	if(__traits(hasMember, T, "SubFields")) {
		foreach(string field; T.SubFields) {
			alias ChildT = ForeachType!(typeof(__traits(getMember, T, field)));
			
			auto stmt = db.prepare("SELECT * FROM "~ChildT.stringof~" WHERE "~ChildFkField!(T, ChildT)~" = ?;");
			stmt.bind(1, obj.id.get);
			__traits(getMember, obj, field) = stmt.execute().map!(row => this.loadFromRow!ChildT(row)).array;
		}
	}
	private void loadSubObjects(T)(T obj)
	if(!__traits(hasMember, T, "SubFields")) {
		// nothing to load
	}
	
	/**
	 * Reads a model and its submodules form the save file.
	**/
	T loadByID(T)(ulong objId)
	if(staticIndexOf!(T, AllModels) != -1) {
		auto stmt = db.prepare("SELECT * FROM "~T.stringof~" WHERE id = ?;");
		stmt.bind(1, objId);
		auto rows = stmt.execute();
		
		if(rows.empty)
			return null;
		return loadFromRow!(T)(rows.front);
	}
	
	/**
	 * Updates or creates a model and its submodels.
	 * You probably want to run this in a transaction.
	 */
	void save(T, Args...)(T obj, Args toTupleArgs)
	if(staticIndexOf!(T, AllModels) != -1) {
		enum InsertStmt = "INSERT OR REPLACE INTO "~T.stringof~" VALUES ("~repeat("?", T.ReprTuple.Types.length+1).join(",")~");";
		
		auto tup = obj.toTuple(toTupleArgs);
		auto stmt = db.prepare(InsertStmt);
		
		stmt.bind(1, obj.id);
		foreach(i, ref item; tup.expand) {
			static if(is(typeof(item) : ForeignKey!Typ, Typ))
				stmt.bind(i+2, item.id);
			else static if(is(typeof(item) : ModelUnique!Typ, Typ))
				stmt.bind(i+2, item._val);
			else
				stmt.bind(i+2, item);
		}
		
		stmt.execute();
		if(obj.id.isNull)
			obj.id = db.lastInsertRowid();
		
		static if(__traits(hasMember, T, "SubFields"))
		foreach(string field; T.SubFields) {
			alias ChildT = ForeachType!(typeof(__traits(getMember, T, field)));
			stmt = db.prepare("DELETE FROM "~ChildT.stringof~" WHERE id = ?;");
			stmt.bind(1, obj.id);
			stmt.execute();
			
			foreach(ref subobj; __traits(getMember, obj, field))
				this.save(subobj, obj);
		}
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
	SaveState loadState(string stateName) {
		auto stmt = db.prepare(`SELECT * FROM SaveStates WHERE label = ?;`);
		stmt.bind(1, stateName);
		auto results = stmt.execute();
		
		if(results.empty)
			return null;
		
		auto result = results.front;
		
		ubyte[] registersBytes = result.peek!(ubyte[])(2);
		enforce(registersBytes.length == Registers.sizeof, "Saved registers do not match the current architecture.");
		
		SaveState state = new SaveState();
		with(state) {
			id = result.peek!ulong(0);
			name = result.peek!string(1);
			registers = *(cast(Registers*) registersBytes);
			
			realtime = Clock(result.peek!ulong(3), result.peek!ulong(4));
			monotonic = Clock(result.peek!ulong(5), result.peek!ulong(6));
			
			windowSize = result.columnType(7) == SqliteType.NULL ?
				typeof(SaveState.windowSize)() :
				typeof(SaveState.windowSize)(tuple(result.peek!uint(7), result.peek!uint(8)));
			
			stmt = db.prepare(`SELECT * FROM MemoryMappings WHERE saveState = ?;`);
			stmt.bind(1, id.get);
			maps = stmt.execute().map!(x => readMemoryMap(x)).array();
			
			stmt = db.prepare(`SELECT * FROM Files WHERE saveState = ?;`);
			stmt.bind(1, id.get);
			files = stmt.execute().map!(x => readFileDescriptor(x)).array();
		}
		
		return state;
	}
	
	/// Loads one map from the database
	MemoryMap getMap(ulong id) {
		auto stmt = db.prepare(`SELECT * FROM MemoryMappings WHERE rowid = ?;`);
		stmt.bind(1, id);
		auto results = stmt.execute();
		
		if(results.empty)
			return null;
		auto row = results.front;
		return readMemoryMap(row);
	}
	
	/**
	 * Writes a modified memory map to the savefile.
	 * TODO: Currently only updates the contents, and only works on anonymous maps.
	 */
	void updateMap(const MemoryMap map)
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
		MemoryMap map = new MemoryMap();
		with(map) {
			id = row.peek!ulong(0);
			begin = row.peek!ulong(2);
			end = row.peek!ulong(3);
			flags =
				(row.peek!bool(4) ? MemoryMapFlags.READ : 0) |
				(row.peek!bool(5) ? MemoryMapFlags.WRITE : 0) |
				(row.peek!bool(6) ? MemoryMapFlags.EXEC : 0) |
				(row.peek!bool(7) ? MemoryMapFlags.PRIVATE : 0);
			name = row.peek!string(8);
			offset = row.peek!ulong(9);
			contents = cast(const(ubyte)[]) uncompress(
				row.peek!(ubyte[])(10),
				row.peek!ulong(3) - row.peek!ulong(2)
			);
		}
		return map;
	}
	
	private FileDescriptor readFileDescriptor(Row row) {
		FileDescriptor file = new FileDescriptor();
		with(file) {
			id = row.peek!ulong(0);
			descriptor = row.peek!int(2);
			fileName = row.peek!string(3);
			pos = row.peek!ulong(4);
			flags = row.peek!int(5);
		}
		return file;
	}
}

private {
	template SQLType(T) {
		static if(is(T : Nullable!Args, Args...)) {
			alias U = Args[0];
			enum canBeNull = "";
		} else {
			alias U = T;
			enum canBeNull = " NOT NULL";
		}
		
		
		static if(is(U : ModelUnique!Args, Args...)) {
			alias V = Args[0];
			enum isUnique = " UNIQUE";
		} else {
			alias V = U;
			enum isUnique = "";
		}
		
		alias BaseType = V;
		enum annotations = canBeNull ~ isUnique;
		
		static if(isIntegral!BaseType || is(BaseType : bool))
			enum SQLType = "INT"~annotations;
		else static if(isSomeString!BaseType)
			enum SQLType = "TEXT"~annotations;
		else static if(is(BaseType : const(ubyte)[]))
			enum SQLType = "BLOB"~annotations;
		else static if(is(BaseType : ForeignKey!Args, Args...))
			enum SQLType = "INT"~annotations~" REFERENCES "~Args[0].stringof~"(id) ON DELETE CASCADE";
		else
			static assert(false, "Don't know how to convert "~BaseType.stringof~" to a SQLite type.");
	}
	
	enum ChildFkField(Parent, Child) = Child.ReprTuple.fieldNames[staticIndexOf!(ForeignKey!Parent, Child.ReprTuple.Types)];

	template SchemaFor(T) {
		alias ReprTuple = T.ReprTuple;
		template ColumnDecl(string field) {
			enum ColumnDecl = field ~ " " ~ SQLType!(ReprTuple.Types[staticIndexOf!(field, ReprTuple.fieldNames)]);
		}
		
		enum SchemaFor = "CREATE TABLE IF NOT EXISTS "~T.stringof~" (\n"~
			(
				["id INTEGER PRIMARY KEY AUTOINCREMENT"] ~
				[staticMap!(ColumnDecl, ReprTuple.fieldNames)]
			).join(",\n")
		~ ");";
	}

	enum Schema = `
		PRAGMA journal_mode = WAL;
		PRAGMA foreign_keys = ON;
	` ~ [staticMap!(SchemaFor, AllModels)].join("\n");
}

unittest {
	auto file = SaveStatesFile(":memory:");
	
	auto map = new MemoryMap();
	with(map) {
		id = 1;
		begin = 123;
		end = begin + 3;
		flags = MemoryMapFlags.READ;
		name = "[heap]";
		offset = 0;
		contents = [1,2,3];
	}
	
	auto state = new SaveState();
	with(state) {
		id = 1;
		name = "asdf";
		maps = [map];
		files = [];
		realtime = Clock(123, 456);
		monotonic = Clock(789, 12);
		windowSize = Tuple!(uint, uint)(800, 600);
	}
	file.save(state);
	
	auto map2 = file.loadByID!MemoryMap(1);
	assert(map.id == map2.id);
	assert(map.begin == map2.begin);
	assert(map.end == map2.end);
	assert(map.flags == map2.flags);
	assert(map.name == map2.name);
	assert(map.offset == map2.offset);
	assert(map.contents == map2.contents);
	
	auto state2 = file.loadByID!SaveState(1);
	assert(state.id == state2.id);
	assert(state.name == state2.name);
	assert(state.maps.length == state2.maps.length);
	assert(state.maps[0].id == state2.maps[0].id);
	assert(state.files == state2.files);
	assert(state.realtime == state2.realtime);
	assert(state.monotonic == state2.monotonic);
	assert(state.windowSize == state2.windowSize);
	
	auto map3 = file.loadByID!MemoryMap(123);
	assert(map3 is null);
}
