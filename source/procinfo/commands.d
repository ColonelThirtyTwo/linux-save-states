
/// Defines tracer/tracee communication commands
module procinfo.commands;

import std.string : format;

/// Commands passed from the wrapper proc to the traced proc. See `resources/wrapper2appcmds`.
mixin(q{
	enum Wrapper2AppCmd {
		%s
	};
}.format(import("wrapper2appcmds")));

/// Commands passed from the traced proc to the wrapper proc. See `resources/app2wrappercmds`.
mixin(q{
	enum App2WrapperCmd {
		%s
	};
}.format(import("app2wrappercmds")));
