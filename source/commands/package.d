
module commands;

import std.format : format;
import std.string;
import std.traits;

public import commands.savefile;
public import commands.execute;

enum PROGNAME = "linux-save-state";

template CommandName(alias cmd) {
	static if(isSomeFunction!cmd)
		enum cmdstr = __traits(identifier, cmd);
	else
		enum cmdstr = cmd;
	enum CommandName = cmdstr[4..$].replace("_", "-");
}

/// Gets help text for a command
template Help(alias cmd) {
	enum Help = "Usage: " ~ PROGNAME ~ " " ~ CommandName!cmd ~ " " ~
		__traits(getAttributes, cmd)[0] ~ "\n" ~
		__traits(getAttributes, cmd)[1];
}

/// Mixin: checks args for -h/--help, and prints USAGE if found.
template ARG_HELP(alias cmd) {
	enum ARG_HELP = q{
		if(args.canFind("--help") || args.canFind("-h")) {
			writeln(`%s`);
			return 0;
		}
	}.format(Help!cmd);
}

/// Mixin: Prints usage and errors out if args does not contain exactly n elements
template ARG_NUM_REQUIRED(alias cmd, uint n) {
	enum ARG_NUM_REQUIRED = q{
		if(args.length != %d) {
			stderr.writeln(`%s`);
			return 1;
		}
	}.format(n, Help!cmd);
}

/// Mixin: Opens the save states file as variable `saveStateFile` and begins a transaction.
enum OPEN_SAVESTATES = q{
	auto saveStatesFile = SaveStatesFile("savestates.db");
	scope(exit) saveStatesFile.close();
	
	saveStatesFile.db.begin();
	scope(success) saveStatesFile.db.commit();
	scope(failure) if(!saveStatesFile.db.isAutoCommit) saveStatesFile.db.rollback();
};
