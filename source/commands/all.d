
module commands.all;

import std.algorithm;
import std.array;
import std.typetuple;

import commands;

private template Import(string name) {
	enum Import = q{
		public import commands.NAME;
		import cmds_NAME = commands.NAME;
	}.replace("NAME", name);
}

mixin(Import!"savefile");
mixin(Import!"execute");
mixin(Import!"savestate");

/// Names of all known commands
alias AllCommands = Filter!(IsCommand,
	__traits(allMembers, cmds_savefile),
	__traits(allMembers, cmds_execute),
	__traits(allMembers, cmds_savestate),
);

/// Names of commands who are accessible from the command line
alias ProgCommands = Filter!(templateNot!IsShellOnly, AllCommands);
/// Names of commands who are accessible from the tracer shell
alias ShellCommands = Filter!(templateNot!IsCliOnly, AllCommands);

/// Command-line help text
enum PROG_USAGE = `Usage: linux-save-state <command>
A tool for saving and restoring linux processes.
Save states are stored in a savestates.db file in the current directory.

Most of the time, you want to use:
	linux-save-state execute <exe> [arg ...]
to start tracing a process and start a shell.

Available CLI commands:
` ~ [staticMap!(CommandName, ProgCommands)]
	.sort()
	.map!(x => "* " ~ x)
	.join("\n");

/// Tracer shell help text
enum SHELL_USAGE = `
Run "<command> --help" to display usage for a specific command.

Available commands:
` ~ ([staticMap!(CommandName, ShellCommands)] ~ ["c", "continue"])
	.sort()
	.map!(x => "* " ~ x)
	.join("\n");
