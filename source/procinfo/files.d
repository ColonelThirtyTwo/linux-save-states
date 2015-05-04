module procinfo.files;

import std.stdio;
import std.file;
import std.conv : to;
import std.format : format;
import std.string : chomp, chompPrefix;
import std.algorithm;
import std.range;
import std.regex;
import std.typecons : Nullable;
import std.c.linux.linux : pid_t;

import models;
import procinfo;
import procinfo.cmdpipe;
import procinfo.tracer : WaitEvent;

/// Reads all of the file descriptors of a process and returns a range of FileDescriptor structs.
/// The process should be paused during this.
/// Stdin/out/err and the command pipes are excluded from being saved.
auto readFiles(pid_t pid) {
	// TODO: replace stderr.writeln with logging
	alias specialLinkRE = ctRegex!`^([a-zA-Z0-9_]*):\[?([^\]]+)\]?$`;
	alias fdInfoRE = ctRegex!(`^pos:\s+([0-9]+)\s+flags:\s+([0-9]+)\s*$`);
	
	return dirEntries("/proc/"~to!string(pid)~"/fd/", SpanMode.shallow)
		.map!(delegate(DirEntry dir) {
			int fd = dir.name.findSplitAfter("/fd/")[1].to!int;
			if(fd <= 2 || fd == APP_READ_FD || fd == APP_WRITE_FD)
				// Skip stdin/out/err and the command pipe
				return Nullable!FileDescriptor();
			
			string link = readLink(dir.name);
			
			auto linkMatch = link.matchFirst(specialLinkRE);
			if(linkMatch) {
				stderr.writeln("! File descriptor %d won't be saved: doesn't point to a file (it's a %s)"
					.format(fd, linkMatch[1] == "anon_inode" ? linkMatch[2] : linkMatch[1]));
				return Nullable!FileDescriptor();
			}
			
			if(!link.isFile) {
				stderr.writeln("! File descriptor %d won't be saved: file %s is not a regular file".format(fd, link));
				return Nullable!FileDescriptor();
			}
			
			string fdInfoText = cast(string) read("/proc/"~to!string(pid)~"/fdinfo/"~to!string(fd));
			auto fdInfoMatch = fdInfoText.matchFirst(fdInfoRE);
			assert(fdInfoMatch, "Error parsing file descriptor info. Contents:\n"~fdInfoText);
			
			FileDescriptor file = {
				descriptor: fd,
				fileName: link,
				pos: fdInfoMatch[1].to!ulong,
				flags: fdInfoMatch[2].to!int(8),
			};
			return Nullable!FileDescriptor(file);
		})
		.filter!(x => !x.isNull)
		.map!(x => x.get)
	;
}

/// Closes all open files of a process and loads the passed list of files.
/// stdin/out/err and the command pipes are skipped.
void loadFiles(Range)(auto ref ProcInfo proc, Range newFiles)
if(isInputRange!Range && is(ElementType!Range : FileDescriptor)) {
	// Need to resume the tracee before writing to the pipe, so that it can drain the pipe
	// if it overfills.
	foreach(fd; getFileDescriptors(proc.pid)) {
		proc.tracer.resume();
		proc.commandPipe.write(Wrapper2AppCmd.CMD_CLOSE);
		proc.commandPipe.write!int(fd);
		
		while(proc.tracer.wait() != WaitEvent.PAUSE)
			proc.tracer.resume();
	}
	
	foreach(file; newFiles) {
		proc.tracer.resume();
		proc.commandPipe.write(Wrapper2AppCmd.CMD_OPEN);
		proc.commandPipe.write!string(file.fileName);
		proc.commandPipe.write!int(file.descriptor);
		proc.commandPipe.write!int(file.flags);
		proc.commandPipe.write!ulong(file.pos);
		
		while(proc.tracer.wait() != WaitEvent.PAUSE)
			proc.tracer.resume();
	}
}

/// Returns a range of int file descriptors.
/// Skips stdin/out/err and the command pipes.
auto getFileDescriptors(pid_t pid) {
	return dirEntries("/proc/"~to!string(pid)~"/fd/", SpanMode.shallow)
		.map!(x => x.name.findSplitAfter("/fd/")[1].to!int)
		.filter!(x => !(x <= 2 || x == APP_READ_FD || x == APP_WRITE_FD))
	;
}
