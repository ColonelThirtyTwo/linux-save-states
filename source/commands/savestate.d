/// Commands for loading and saving state.
module commands.savestate;

import std.stdio;

import models;
import savefile;
import commands;
import global;

@("<label>")
@(`Saves the state.`)
@ShellOnly
int cmd_save(string[] args) {
	if(args.length != 1) {
		writeln("Usage: s[ave] <label>");
		return 1;
	}
	
	{
		// Put this in a new scope so that "state saved" prints when the transaction is commited and the state
		// is actually saved.
		mixin(Transaction!saveFile);
		saveFile.save(process.saveState(args[0]));
	}
	
	writeln("state saved");
	return 0;
}
alias cmd_s = cmd_save;

@("<label>")
@(`Loads a state`)
@ShellOnly
int cmd_load(string[] args) {
	if(args.length != 1) {
		writeln("Usage: l[oad] <label>");
		return 1;
	}
	mixin(Transaction!saveFile);
	
	auto state = saveFile.loadByField!(SaveState, "name")(args[0]);
	if(state is null) {
		writeln("No such state.");
		return 1;
	}
	process.loadState(state);
	
	writeln("state loaded");
	return 0;
}
