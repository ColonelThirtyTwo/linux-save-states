/// Open file inspection
module procinfo.files;

import std.stdio;
import std.file;
import std.conv : to;
import std.format : format;
import std.string : chomp, chompPrefix;
import std.algorithm;
import std.range;
import std.traits;
import std.typetuple;
import std.regex;
import std.typecons : Nullable, Tuple, tuple;
import std.c.linux.linux : pid_t;

import models;
import procinfo.proc;
import procinfo.commands;
import procinfo.cmdpipe : AllSpecialFileDescriptors;

private {
	alias specialLinkRE = ctRegex!`^([a-zA-Z0-9_]*):\[?([^\]]+)\]?$`;
	alias fdInfoRE = ctRegex!(`^pos:\s+([0-9]+)\s+flags:\s+([0-9]+)\s*$`);
}

/++
 + Reads all of the file descriptors of a process and returns a range of FileDescriptor structs.
 +
 + The process should be paused during this. Descriptors in $(D procinfo.cmdpipe.AllSpecialFileDescriptors)
 + will be ignored.
++/
auto readFiles(pid_t pid) {
	return getFileDescriptors(pid)
		.map!(delegate(fd) {
			auto link = canSave(pid, fd);
			if(!link[0]) {
				stderr.writeln("! File descriptor %d won't be saved: %s".format(fd, link[1]));
				return null;
			}
			
			string fdInfoText = cast(string) read("/proc/"~to!string(pid)~"/fdinfo/"~to!string(fd));
			auto fdInfoMatch = fdInfoText.matchFirst(fdInfoRE);
			assert(fdInfoMatch, "Error parsing file descriptor info. Contents:\n"~fdInfoText);
			
			FileDescriptor file = new FileDescriptor();
			
			file.descriptor = fd;
			file.fileName = link[1];
			file.pos = fdInfoMatch[1].to!ulong;
			file.flags = fdInfoMatch[2].to!int(8);
			
			return file;
		})
		.filter!(x => x !is null)
	;
}

/++ Closes all open files of a process and loads the passed list of files.
 +
 + The process should be paused during this. Descriptors in $(D procinfo.cmdpipe.AllSpecialFileDescriptors)
 + will be ignored.
++/
void loadFiles(Range)(ProcInfo proc, Range newFiles)
if(isInputRange!Range && is(ElementType!Range : const(FileDescriptor))) {
	auto pid = proc.pid;
	getFileDescriptors(pid)
		.filter!(delegate(fd) {
			auto link = canSave(pid, fd);
			if(!link[0]) {
				stderr.writeln("! File descriptor %d won't be closed: %s".format(fd, link[1]));
				return false;
			}
			return true;
		})
		.each!((int fd) => proc.write(Wrapper2AppCmd.CMD_CLOSE, fd));
	
	newFiles
		.each!(file => proc.write(
			Wrapper2AppCmd.CMD_OPEN,
			file.fileName,
			file.descriptor,
			file.flags,
			file.pos
		));
}

/++ Returns a range of int file descriptors.
 +
 + The process should be paused during this. Descriptors in $(D procinfo.cmdpipe.AllSpecialFileDescriptors)
 + will be ignored.
++/
auto getFileDescriptors(pid_t pid) {
	return dirEntries("/proc/"~to!string(pid)~"/fd/", SpanMode.shallow)
		.map!(x => x.name.findSplitAfter("/fd/")[1].to!int)
		.filter!(x => !AllSpecialFileDescriptors.canFind(x))
	;
}

private Tuple!(bool, string) canSave(pid_t pid, int fd) {
	string link = readLink("/proc/%d/fd/%d".format(pid, fd));
	
	auto linkMatch = link.matchFirst(specialLinkRE);
	if(linkMatch)
		return tuple(false, "doesn't point to a file, it's a "~(linkMatch[1] == "anon_inode" ? linkMatch[2] : linkMatch[1]));
	
	if(!link.isFile)
		return tuple(false, "points to "~link~" which is not a regular file");
	
	return tuple(true, link);
}
