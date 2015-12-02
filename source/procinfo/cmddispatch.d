/// Parses and executes commands from the tracee.
module procinfo.cmddispatch;

import std.string : toLower;
import std.conv : to;
import std.typecons : Nullable;

import procinfo.proc;
import procinfo.commands;

/++
 + Takes a command ID and runs the appropriate command.
 +
 + Commands are specified as private methods of the form `cmd_somecommand` (all lowercase), where
 + `somecommand` is a value in the `app2wrappercmds` file in `resources/`.
 +
 + OpenGL commands are process separately, in `GLDispatch`.
++/
struct CommandDispatcher {
	void execute(App2WrapperCmd cmd, ProcInfo proc) {
		final switch(cmd) {
			foreach(CommandName; __traits(allMembers, App2WrapperCmd)) {
				case __traits(getMember, App2WrapperCmd, CommandName):
					static assert(
						__traits(compiles, __traits(getMember, this, CommandName.toLower())(proc)),
						"Function for "~CommandName~" doesn't exist or is ill-defined."
					);
					return __traits(getMember, this, CommandName.toLower())(proc);
			}
		}
		assert(false, "Unrecognized command: "~to!string(cast(int)cmd));
	}
	
private:
	void cmd_test(ProcInfo proc) {
		import std.stdio;
		auto data = proc.read!uint();
		writeln("Test command: received ", data[0]);
	}
	
	void cmd_openwindow(ProcInfo proc) {
		auto size = proc.read!(uint, uint)();
		proc.window.open(size[0], size[1]);
	}
	
	void cmd_closewindow(ProcInfo proc) {
		proc.window.close();
	}
	
	void cmd_resizewindow(ProcInfo proc) {
		auto size = proc.read!(uint, uint)();
		proc.window.resize(size[0], size[1]);
	}
	
	void cmd_swapbuffers(ProcInfo proc) {
		proc.pollGL();
		proc.window.swapBuffers();
	}
}
