PRAGMA foreign_keys = ON;
-- All BLOBs are compressed with zlib unless otherwise noted.

BEGIN;

CREATE TABLE IF NOT EXISTS SaveStates (
	rowid INTEGER PRIMARY KEY,
	label TEXT UNIQUE
);

CREATE TABLE IF NOT EXISTS MemoryMappings (
	saveState INT NOT NULL REFERENCES SaveStates(rowid) ON DELETE CASCADE,
	startPtr INT NOT NULL,
	endPtr INT NOT NULL,
	
	readMode INT NOT NULL,
	writeMode INT NOT NULL,
	execMode INT NOT NULL,
	privateMode INT NOT NULL,
	
	fileName TEXT,
	fileOffset INT,
	
	contents BLOB,
	
	CHECK(endptr >= startptr)
);

COMMIT;
