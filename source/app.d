
import std.stdio;
import std.conv : to, ConvException;
import std.algorithm;
import std.range;
import std.typecons;
import std.typetuple;

import commands : CommandName;
import allcmds = commands.all;

import savefile;
import global;

version(unittest) {
	void main(string[] args) {
		stdout.writeln("All tests completed.");
	}
} else {
	int main(string[] args) {
		if(args.length < 2) {
			stderr.writeln(allcmds.PROG_USAGE);
			return 1;
		}

		if(args[1] == "--help" || args[1] == "-h" || args[1] == "help") {
			writeln(allcmds.PROG_USAGE);
			return 0;
		}
		
		saveFile = SaveStatesFile("savestates.db");
		scope(exit) saveFile.close();
		
		switch(args[1]) {
			foreach(member; allcmds.ProgCommands) {
				case CommandName!member:
					return __traits(getMember, allcmds, member)(args[2..$]);
			}
			default:
				stderr.writeln(allcmds.PROG_USAGE);
				stderr.writeln("No such command: "~args[1]);
				return 1;
		}
	}
}