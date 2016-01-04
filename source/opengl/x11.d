///
module opengl.x11;

import std.conv;
import std.bitmanip;
import std.traits;
import std.string;
import std.exception;
import std.range;
import std.algorithm;
import core.thread;

import procinfo.pipe;

/// Thrown on a protocol error (ex. receiving invalid data)
final class X11ProtocolException : Exception {
	this(string msg, string file=__FILE__, size_t line=__LINE__) {
		super(msg);
	}
}

// stolen from std.algorithm.common (where it is package-private)
private size_t roundUpToMultipleOf(size_t s, uint base)
{
    assert(base);
    auto rem = s % base;
    return rem ? s + base - rem : s;
}

private string assumeSring(ubyte[] buf) {
	return buf.assumeUTF.assumeUnique;
}

private size_t pad(size_t n) {
	return roundUpToMultipleOf(n, 4);
}

/++
 + 
++/
final class X11Dispatcher {
	// http://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.html
	
	this(Pipe pipe) {
		this.pipe = pipe;
		this.fiber = new Fiber(&this.main);
	}
	
	void poll() {
		if(this.fiber.state != Fiber.State.TERM)
			this.fiber.call();
	}
	
private:
	Pipe pipe;
	Fiber fiber;
	bool isLittleEndian;
	
	version(unittest) {
		bool testing = false;
		const(ubyte)[] testInput;
		ubyte[] testOutput;
	}
	
	void rawRead(void[] buf) {
		version(unittest) if(testing) {
			if(buf.length > testInput.length)
				throw new PipeClosedException();
			buf[] = testInput[0..buf.length].dup;
			testInput = testInput[buf.length..$];
			return;
		}
		
		while(buf.length != 0) {
			auto partRead = buf;
			this.pipe.read(partRead);
			if(partRead.ptr is null)
				// Yield until we have more data to read.
				Fiber.yield();
			else
				buf = buf[partRead.length..$];
		}
	}
	
	/// Reads a buffer of `length` bytes
	T read(T)(size_t length)
	if(is(T : ubyte[])) {
		if(length == 0)
			return null;
		
		auto buf = new ubyte[](length);
		rawRead(buf);
		return buf;
	}
	
	/// Reads a single byte
	T read(T)()
	if(is(T : ubyte)) {
		ubyte[1] buf;
		rawRead(buf[]);
		return buf[0];
	}
	
	/// Reads an integer, doing endian conversion.
	T read(T)()
	if(isIntegral!T && !is(T : ubyte)) {
		ubyte[T.sizeof] buf;
		rawRead(buf[]);
		if(isLittleEndian)
			return littleEndianToNative!(T)(buf);
		else
			return bigEndianToNative!(T)(buf);
	}
	
	
	
	void write(T)(T data)
	if(is(T : const(ubyte)[])) {
		version(unittest) if(testing) {
			testOutput ~= data;
			return;
		}
		
		pipe.write(data);
	}
	
	void write(T)(T data)
	if(is(T : ubyte)) {
		this.write((&data)[0..1]);
	}
	
	void write(T)(T data)
	if(isIntegral!T && !is(T : ubyte)) {
		ubyte[T.sizeof] buf;
		if(isLittleEndian)
			buf = nativeToLittleEndian(data);
		else
			buf = nativeToBigEndian(data);
		this.write(buf[]);
	}
	
	
	
	void main() {
		try {
			connectionSetup();
			
			while(true) {
				ubyte opcode = read!ubyte();
				ushort length = read!ushort();
				ubyte data = read!ubyte();
			}
		} catch(PipeClosedException) {
			return;
		}
	}
	
	void connectionSetup() {
		// read byte order byte
		auto byteOrder = read!ubyte();
		if(byteOrder == octal!102)
			isLittleEndian = false;
		else if(byteOrder == octal!154)
			isLittleEndian = true;
		else
			throw new X11ProtocolException("Received invalid endian indicator");
		
		read!ubyte(); // unused
		
		auto majorVersion = read!ushort();
		auto minorVersion = read!ushort();
		
		auto authNameLen = read!ushort();
		auto authDataLen = read!ushort();
		
		read!ubyte(); // unused
		
		auto authName = read!(ubyte[])(pad(authNameLen))[0..authNameLen].assumeSring;
		auto authData = read!(ubyte[])(pad(authDataLen))[0..authDataLen];
		
		if(majorVersion != 11 && minorVersion != 0)
			throw new X11ProtocolException(text("Unsupported X11 version: ", majorVersion, ".", minorVersion));
		
		immutable vendor = "Linux-Save-States";
		immutable ubyte[] padding = [0,0,0,0,0];
		
		write!ubyte(1); // success
		write!ubyte(0); // unused
		write!ushort(11); // major version
		write!ushort(0); // minor version
		write!ushort(cast(ushort)(
			8+ // constant overhead
			2*1+ // formats
			10*1+ // screens
			2*1+ // depths
			6*1+ // visuals
			pad(vendor.representation.length)/4 // vendor string
		)); // additional data length
		// TODO: ^ inaccurate
		
		write!uint(1); // release number
		write!uint(0); // resource ID base
		write!uint(0x001FFFFF); // resource ID mask
		write!uint(0xFF); // motion buffer size
		write!ushort(cast(ushort) vendor.representation.length); // vendor string length
		write!ushort(0xFFFF); // maximum request length
		write!ubyte(1); // num of screens in roots
		write!ubyte(1); // num of formats in pixmap-formats
		version(LittleEndian) {
			write!ubyte(0); // image byte order
			write!ubyte(0); // bitmap format bit order
		} else {
			write!ubyte(1); // same as above
			write!ubyte(1);
		}
		write!ubyte(32); // bitmap scanline units
		write!ubyte(32); // bitmap scanline padding
		write!ubyte(8); // min keycode
		write!ubyte(255); // max keycode
		write!uint(0); // unused
		write(vendor.representation); // vendor (and padding)
		write(padding[0..(pad(vendor.representation.length) - vendor.representation.length)]);
		
		// Pixmap formats
		write!ubyte(32); // depth
		write!ubyte(32); // pixel alignment
		write!ubyte(32); // scanline alignment
		write(padding[0..5]); // unused
		
		// Screens
		write!uint(1); // root window ID
		write!uint(1); // default colormap id
		write!uint(0x00FFFFFF); // white pixel value
		write!uint(0x00000000); // black pixel value
		write!uint(0x00fa3f80); // input masks (TODO: Stolen from my laptop, determine format and significance)
		write!ushort(1920); // screen pixel width (TODO: make this configurable)
		write!ushort(1080); // screen pixel height
		write!ushort(0x01fc); // screen mm width (TODO: stolen from my laptop, probably not significant)
		write!ushort(0x011d); // screen mm height
		write!ushort(1); // min installed maps
		write!ushort(1); // max installed maps
		write!uint(1); // root visual ID
		write!ubyte(1); // backing stores (= when mapped)
		write!ubyte(0); // save unders (= false)
		write!ubyte(24); // root depth
		write!ubyte(1); // number of depths
		
		// Depths
		write!ubyte(24); // depth
		write!ubyte(0); // unused
		write!ushort(1); // number of visual types
		write!uint(0); // unused
		
		// Visuals for depth 1
		write!uint(1); // visual ID
		write!ubyte(4); // class (= truecolor)
		write!ubyte(8); // bits per RGB value
		write!ushort(256); // colormap entries
		write!uint(0x00ff0000); // red mask
		write!uint(0x0000ff00); // green mask
		write!uint(0x000000ff); // blue mask
		write!uint(0x00000000); // unused
	}
}

unittest {
	auto srv = new X11Dispatcher(Pipe.init);
	srv.testing = true;
	srv.testInput = cast(immutable(ubyte)[]) hexString!"
		6c000b0000001200100000004d49542d4d414749432d434f4f4b49452d31
		0000deadbeef000000000000000000000000
	";
	
	srv.poll();
	assert(srv.testOutput.canFind("Linux-Save-States".representation));
}
