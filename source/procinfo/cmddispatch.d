/// Parses and executes commands from the tracee.
module procinfo.cmddispatch;

import std.string : toLower;
import std.conv : to;

import procinfo.cmdpipe;

struct CommandDispatcher {
	void execute(ref CommandPipe pipe) {
		App2WrapperCmd cmd;
		try {
			cmd = pipe.read!App2WrapperCmd();
		} catch (PipeClosedException ex) {
			return;
		}
		
		final switch(cmd) {
			foreach(CommandName; __traits(allMembers, App2WrapperCmd)) {
				case __traits(getMember, App2WrapperCmd, CommandName):
					static assert(
						__traits(compiles, __traits(getMember, this, CommandName.toLower())(pipe)),
						"Function for "~CommandName~" doesn't exist or is ill-defined."
					);
					return __traits(getMember, this, CommandName.toLower())(pipe);
			}
		}
		assert(false, "Unrecognized command: "~to!string(cast(int)cmd));
	}
	
	private {
		void cmd_test(ref CommandPipe pipe) {
			import std.stdio;
			auto data = pipe.read!uint();
			writeln("Test command: received ", data);
		}
	}
}
