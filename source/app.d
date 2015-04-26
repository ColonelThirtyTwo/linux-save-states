
import std.stdio;
import core.sys.posix.unistd;
import std.conv : to, ConvException;
import std.algorithm : canFind, startsWith, joiner, filter, map;
import std.range : array, replace;

import cmds = commands;

enum USAGE = `Usage: linux-save-state <command>
A tool for saving and restoring linux processes.
Save states are stored in a savestates.db file in the current directory.

Command is one of:
` ~ [__traits(allMembers, cmds)]
	.filter!(x => x.startsWith("cmd_"))
	.map!(x => "* " ~ replace(x[4..$], "_", "-"))
	.joiner("\n")
	.array;

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
		foreach(member; __traits(allMembers, cmds)) {
			static if(member.startsWith("cmd_")) {
				case replace(member[4..$], "_", "-"):
					return __traits(getMember, cmds, member)(args[2..$]);
			}
		}
		default:
			stderr.writeln(USAGE);
			stderr.writeln("No such command: "~args[1]);
			return 1;
	}
}
