
import std.stdio;
import std.conv : to, ConvException;
import std.algorithm;
import std.range;
import std.typecons;

import commands : FilterCommands, CommandName;
import cmds_savefile = commands.savefile;
import cmds_execute = commands.execute;
import cmds = commands;

// Grab all functions in the commands module that start with `cmd_` and
// generate commands for them.
alias AllCommandMembers = FilterCommands!(
	__traits(allMembers, cmds_savefile),
	__traits(allMembers, cmds_execute),
);

enum USAGE = `Usage: linux-save-state <command>
A tool for saving and restoring linux processes.
Save states are stored in a savestates.db file in the current directory.

Command is one of:
` ~ [AllCommandMembers]
	.sort()
	.map!(x => "* " ~ replace(x[4..$], "_", "-"))
	.joiner("\n")
	.array();

int main(string[] args) {

	if(args.length < 2) {
		stderr.writeln(USAGE);
		return 1;
	}

	if(args[1] == "--help" || args[1] == "-h" || args[1] == "help") {
		writeln(USAGE);
		return 0;
	}
	
	switch(args[1]) {
		foreach(member; AllCommandMembers) {
			case CommandName!member:
				return __traits(getMember, cmds, member)(args[2..$]);
		}
		default:
			stderr.writeln(USAGE);
			stderr.writeln("No such command: "~args[1]);
			return 1;
	}
}
