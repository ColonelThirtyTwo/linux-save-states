PRAGMA foreign_keys = ON;

BEGIN;

-- See models.d for documentation of what each of these tables means.

CREATE TABLE IF NOT EXISTS Settings (
	name TEXT PRIMARY KEY NOT NULL,
	value NONE
);
INSERT OR IGNORE INTO Settings VALUES ('frameRate', 16666666); -- 1/60 seconds in nanoseconds

CREATE TABLE IF NOT EXISTS SaveStates (
	rowid INTEGER PRIMARY KEY AUTOINCREMENT, -- rowid is used to order, so make it monotonically increasing
	label TEXT NOT NULL UNIQUE,
	
	registers BLOB NOT NULL,
	
	realtimeSeconds INT NOT NULL,
	realtimeNanoseconds INT NOT NULL,
	monotonicSeconds INT NOT NULL,
	monotonicNanoseconds INT NOT NULL
);

CREATE TABLE IF NOT EXISTS MemoryMappings (
	rowid INTEGER PRIMARY KEY,
	saveState INT NOT NULL REFERENCES SaveStates(rowid) ON DELETE CASCADE,
	
	startPtr INT NOT NULL,
	endPtr INT NOT NULL,
	
	readMode INT NOT NULL,
	writeMode INT NOT NULL,
	execMode INT NOT NULL,
	privateMode INT NOT NULL,
	
	fileName TEXT,
	fileOffset INT,
	
	-- compressed with zlib
	contents BLOB,
	
	UNIQUE(saveState, startPtr),
	CHECK(endptr >= startptr),
	CHECK((fileName IS NULL AND fileOffset IS NULL) OR (fileName IS NOT NULL AND fileOffset IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS MemoryMappings_saveState ON MemoryMappings(saveState);

CREATE TABLE IF NOT EXISTS Files (
	rowid INTEGER PRIMARY KEY,
	saveState INT NOT NULL REFERENCES SaveStates(rowid) ON DELETE CASCADE,
	
	descriptor INT NOT NULL,
	fileName TEXT NOT NULL,
	pos INT NOT NULL,
	flags INT NOT NULL,
	
	UNIQUE(saveState, descriptor),
	CHECK(pos >= 0),
	CHECK(flags >= 0)
);

COMMIT;
