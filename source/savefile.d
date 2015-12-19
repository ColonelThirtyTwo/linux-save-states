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
	 * Reads a model and its submodules form the save file by its ID.
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
	 * Reads a model and its submodules form the save file by the specified column.
	 * The column should be unique.
	**/
	T loadByField(T, string field)(typeof(__traits(getMember, T, field)) key) {
		auto stmt = db.prepare("SELECT * FROM "~T.stringof~" WHERE "~field~" = ? LIMIT 1;");
		stmt.bind(1, key);
		auto rows = stmt.execute();
		
		if(rows.empty)
			return null;
		return loadFromRow!(T)(rows.front);
	}
	
	/**
	 * Returns a range listing the `field` of all known rows of a model.
	 * Useful, for example, for listing SaveStates by their label.
	**/
	auto list(T, string field)() {
		auto stmt = db.prepare("SELECT "~field~" FROM "~T.stringof~" ORDER BY id;");
		return stmt.execute().map!(row => row[0]);
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
	
	/// Closes the savestate file.
	void close() {
		this.db.close();
	}
}

private {
	// Gets a column declaration entry for a type (ex. `TEXT` or `INT NOT NULL`)
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
	
	// Generates a `CREATE TABLE` statement for a model.
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
		
		CREATE TABLE IF NOT EXISTS Settings (name TEXT PRIMARY KEY NOT NULL, value NONE);
		
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
