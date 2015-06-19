/// CLI commands for both CLI arguments and the `execute` shell.
module commands;

import std.format : format;
import std.string;
import std.traits;
import std.algorithm;
import std.typetuple;

import allCmds = commands.all;

/// Returns true if the specified member is a command.
template IsCommand(alias Member) {
	enum IsCommand = Member.startsWith("cmd_");
}

/// Given a command funciton or string, gets the pretty name of the command.
template CommandName(alias Cmd) {
	static if(isSomeFunction!Cmd)
		enum cmdstr = __traits(identifier, Cmd);
	else
		enum cmdstr = Cmd;
	enum CommandName = cmdstr[4..$].replace("_", "-");
}

/// UDA for restricting where a command may be executed.
/// CliOnly commands may only be executed when starting the process via process arguments.
/// ShellOnly commands may only be executed in the tracer shell.
struct CliOnly {}
/// ditto
struct ShellOnly {}

/// Checks the command for CliOnly
template IsCliOnly(alias Cmd) {
	enum IsCliOnly = staticIndexOf!(CliOnly, __traits(getAttributes, Cmd)) != -1;
}
/// ditto
template IsCliOnly(string Cmd) {
	enum IsCliOnly = IsCliOnly!(__traits(getMember, allCmds, Cmd));
}

/// Checks the command for ShellOnly
template IsShellOnly(alias Cmd) {
	enum IsShellOnly = staticIndexOf!(ShellOnly, __traits(getAttributes, Cmd)) != -1;
}
/// ditto
template IsShellOnly(string Cmd) {
	enum IsShellOnly = IsShellOnly!(__traits(getMember, allCmds, Cmd));
}

/// Gets help text for a command
template Help(alias Cmd) {
	enum Help = "Usage: " ~ CommandName!Cmd ~ " " ~
		__traits(getAttributes, Cmd)[0] ~ "\n" ~
		__traits(getAttributes, Cmd)[1];
}

/// Mixin: checks args for -h/--help, and prints USAGE if found.
template ARG_HELP(alias Cmd) {
	enum ARG_HELP = q{
		if(args.canFind("--help") || args.canFind("-h")) {
			writeln(`%s`);
			return 0;
		}
	}.format(Help!Cmd);
}

/// Mixin: Prints usage and errors out if args does not contain exactly n elements
template ARG_NUM_REQUIRED(alias Cmd, uint n) {
	enum ARG_NUM_REQUIRED = q{
		if(args.length != %d) {
			stderr.writeln(`%s`);
			return 1;
		}
	}.format(n, Help!Cmd);
}
