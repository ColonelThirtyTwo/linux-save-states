
/++
 + OpenGL state objects.
 +
 + In the code, when referencing object IDs, the client ID is used unless otherwise specified.
++/
module opengl.state;

private {
	import std.traits;
	import std.typecons;
	import std.typetuple;
	import std.conv;
	import std.algorithm;
	
	import derelict.opengl3.gl;
	import gl = derelict.opengl3.gl;
	import cerealed;
}

/++
 + Template to supply functions for getting/setting OpenGL state
 + to a UDA.
++/
private struct GlGetSet(alias getter, alias setter) {
	alias Getter = getter;
	alias Setter = setter;
}

/// Mixin for OpenGL objects.
mixin template GLObject() {
	/// OpenGL ID of the object as seen by the tracee.
	GLuint clientId;
	/// Actual OpenGL ID of the object.
	@NoCereal
	GLuint serverId;
	
	/// Retreives the object data from OpenGL and stores it in this object.
	/// Returns this.
	typeof(this) download() {
		assert(clientId != 0);
		assert(serverId != 0);
		foreach(memberName; __traits(allMembers, typeof(this))) {
			mixin("alias attrs = TypeTuple!(__traits(getAttributes, typeof(this)."~memberName~"));");
			//alias attrs = __traits(getAttributes, __traits(getMember, typeof(this), memberName));
			static if(attrs.length > 0 && is(attrs[0] : GlGetSet!Args, Args...)) {
				attrs[0].Getter(__traits(getMember, this, memberName), this);
			}
		}
		return this;
	}
	
	/// Uploads the object data from this object to OpenGL.
	void upload() {
		assert(clientId != 0);
		assert(serverId != 0);
		foreach(memberName; __traits(allMembers, typeof(this))) {
			mixin("alias attrs = TypeTuple!(__traits(getAttributes, typeof(this)."~memberName~"));");
			//alias attrs = __traits(getAttributes, __traits(getMember, typeof(this), memberName));
			static if(attrs.length > 0 && is(attrs[0] : GlGetSet!Args, Args...)) {
				attrs[0].Setter(__traits(getMember, this, memberName), this);
			}
		}
	}
	
	/// Constructs a new, empty buffer.
	this() {}
	
	/// Constructs a new buffer with unfilled contents and the specified ids.
	this(GLuint clientId, GLuint serverId) {
		assert(clientId != 0);
		assert(serverId != 0);
		this.clientId = clientId;
		this.serverId = serverId;
	}
	
	invariant {
		// TODO: Proper ID mapping
		// Ensure that the client and server IDs are the same, so that no
		// client id to server id transforms need to happen. This requires a
		// compatibility profile, to manually pick IDs.
		assert(clientId == 0 || serverId == 0 || clientId == serverId);
	}
}

/++
 + Object that holds all the downloaded OpenGL state.
++/
final class GLState {
	/// OpenGL buffers
	Buffer[] buffers;
	
	/// Serializes the GL state to an array of bytes.
	const(ubyte[]) serialize() {
		auto cerializer = Cerealizer();
		cerializer ~= this;
		return cerializer.bytes;
	}
	
	/// Deserializes a GL state from an array of bytes.
	static GLState deserialize(const(ubyte)[] data) {
		auto decerializer = Decerealizer(data);
		return decerializer.value!GLState();
	}
}

/++
 + Global state object.
 + Has a `clientId` and `serverId`, but they are not used.
 + References to other objects via IDs use the client IDs.
++/
final class GlobalState {
	mixin GLObject!();
	
	@(GlGetSet!(
		(ref data, _) {
			gl.glGetIntegerv(gl.GL_VIEWPORT, data.ptr);
		},
		(ref data, _) {
			gl.glViewport(data[0], data[1], data[2], data[3]);
		}
	))
	int[4] viewport;
	
	@(GlGetSet!(
		(ref data, _) {
			gl.glGetFloatv(gl.GL_DEPTH_RANGE, data.ptr);
		},
		(ref data, _) {
			gl.glDepthRangef(data[0], data[1]);
		}
	))
	float[2] depthRange;
}

/// Buffer object
final class Buffer {
	mixin GLObject!();
	
	@(GlGetSet!(
		(ref data, obj) {
			GLint size;
			glGetNamedBufferParameterivEXT(obj.serverId, GL_BUFFER_SIZE, &size);
			data = new ubyte[size];
			glGetNamedBufferSubDataEXT(obj.serverId, 0, data.length, data.ptr);
		},
		(ref data, obj) {
			//if(obj.isImmutableStorage)
			//	glNamedBufferStorage(id, data.length, data.ptr, obj.usage);
			//else
				glNamedBufferDataEXT(obj.serverId, data.length, data.ptr, obj.usage);
		}
	))
	ubyte[] contents;
	
	@(GlGetSet!(
		(ref data, obj) => glGetNamedBufferParameterivEXT(obj.serverId, GL_BUFFER_USAGE, &data),
		(ref data, _) {} // set handled by contents attr
	))
	int usage;
	
	/+Attr!(
		GLboolean,
		(id) => glGetNamedBufferParameterivEXT(id, GL_BUFFER_IMMUTABLE_STORAGE, &data),
		(id) {} // set handled by contents attr
	) isImmutableStorage;+/
}

// /////////////////////////////////////////////////////////////////////////

unittest {
	static immutable ubyte[] testdata = [1,2,3,4,5];
	
	extern(System) @nogc nothrow static
	void mock_glGetNamedBufferParameterivEXT(GLuint name, GLenum pname, int* params) {
		assert(name == 123);
		if(pname == GL_BUFFER_USAGE)
			*params = GL_STATIC_DRAW;
		else if(pname == GL_BUFFER_SIZE)
			*params = cast(int) testdata.length;
		else
			assert(false);
	}
	extern(System) @nogc nothrow static
	void mock_glGetNamedBufferSubDataEXT(GLuint name, GLintptr offset, GLsizeiptr size, void* data) {
		assert(name == 123);
		assert(offset == 0);
		assert(size == testdata.length);
		
		auto dataslice = cast(ubyte[]) data[0..size];
		dataslice[] = testdata[];
	}
	extern(System) @nogc nothrow static
	void mock_glNamedBufferDataEXT(GLuint name, GLsizeiptr size, const void* data, GLenum usage) {
		assert(name == 123);
		assert(size == testdata.length);
		assert(usage == GL_STATIC_DRAW);
		
		auto dataslice = cast(ubyte[]) data[0..size];
		assert(dataslice.equal(testdata));
	}
	
	
	glGetNamedBufferParameterivEXT = &mock_glGetNamedBufferParameterivEXT;
	glGetNamedBufferSubDataEXT = &mock_glGetNamedBufferSubDataEXT;
	glNamedBufferDataEXT = &mock_glNamedBufferDataEXT;
	
	auto buffer = new Buffer(123, 123);
	buffer.download();
	with(buffer) {
		assert(contents[] == testdata[]);
		assert(usage == GL_STATIC_DRAW);
	}
	
	buffer.upload();
	
	auto encoder = Cerealizer();
	encoder ~= buffer;
	auto decoder = Decerealiser(encoder.bytes);
	auto copiedbuffer = decoder.value!Buffer;
	assert(buffer.contents.equal(copiedbuffer.contents));
	assert(buffer.usage == copiedbuffer.usage);
}
