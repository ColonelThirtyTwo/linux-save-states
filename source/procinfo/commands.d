
/// Defines tracer/tracee communication commands
module procinfo.commands;

import std.string : format;

mixin(q{
	/// Commands passed from the wrapper proc to the traced proc. See `resources/wrapper2appcmds`.
	enum Wrapper2AppCmd {
		%s
	};
}.format(import("wrapper2appcmds")));

mixin(q{
	/// Commands passed from the traced proc to the wrapper proc. See `resources/app2wrappercmds`.
	enum App2WrapperCmd {
		%s
	};
}.format(import("app2wrappercmds")));
