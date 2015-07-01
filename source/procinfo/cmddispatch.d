/// Parses and executes commands from the tracee.
module procinfo.cmddispatch;

import std.string : toLower;
import std.conv : to;

import procinfo;

struct CommandDispatcher {
	void execute(ProcInfo proc) {
		App2WrapperCmd cmd;
		try {
			cmd = proc.read!App2WrapperCmd()[0];
		} catch (PipeClosedException ex) {
			return;
		}
		
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
		proc.glState.openWindow(size[0], size[1]);
	}
	
	void cmd_closewindow(ProcInfo proc) {
		proc.glState.closeWindow();
	}
	
	void cmd_resizewindow(ProcInfo proc) {
		auto size = proc.read!(uint, uint)();
		proc.glState.resizeWindow(size[0], size[1]);
	}
}
