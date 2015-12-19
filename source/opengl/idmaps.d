/// Client-to-server ID mapping
module opengl.idmaps;

import std.range;
import std.array;
import std.algorithm;
import std.typecons;
import std.conv;
import std.traits;
import std.experimental.logger;

import derelict.opengl3.gl;
import cerealed;

import opengl.state;

/++
 + Stores mappings of client-side IDs to server-side IDs for OpenGL objects.
 + 
 + In core OpenGL, the client code cannot pick IDs; the server has to generate them.
 + So we need to store mappings of the IDs that the client knows about with IDs that
 + the server knows about.
 +
 + For each map, the keys are the client-side IDs and the values are the server-side IDs.
 + (In this case, the client is the tracee and the server is the OpenGL implementation)
++/
final class IdMaps {
	/// Map of client to server IDs.
	private uint[uint] bufferIDs;
	
	invariant {
		// TODO: Proper ID mapping
		// Ensure that the client and server IDs are the same, so that no
		// client id to server id transforms need to happen. This requires a
		// compatibility profile, to manually pick IDs.
		assert(bufferIDs.keys.equal(bufferIDs.values));
	}
	
	// ----------------------------------------------------------------------
	
	/++
	 + Downloads the entire OpenGL state.
	++/
	GLState downloadState() {
		auto state = new GLState();
		state.buffers = this.getBuffers().array;
		return state;
	}
	
	/++
	 + Uploads the OpenGL state from a GLState object.
	++/
	void uploadState(GLState state) {
		this.clearBuffers();
		
		state.buffers.each!(buffer => this.loadBuffer(buffer));
	}
	
	// ----------------------------------------------------------------------
	
	/// Looks up a client buffer ID, returning a server ID.
	Nullable!uint lookupBuffer(uint clientId) {
		auto ptr = clientId in bufferIDs;
		if(ptr is null)
			return Nullable!uint();
		else
			return Nullable!uint(*ptr);
	}
	
	/// Gets and downloads all known buffers
	auto getBuffers() {
		return bufferIDs
			.byPair
			.map!(entry => (new Buffer(entry[0], entry[1])).download())
			.takeExactly(bufferIDs.length) // byPair range doesn't have a length
		;
	}
	static assert(hasLength!(ReturnType!getBuffers));
	
	/// Generates `count` new buffers. Returns their client IDs as a range.
	auto newBuffers(uint count) {
		/+
		// TODO: Proper ID mapping
		uint maxId = bufferIDs.length == 0 ? 0 :
			bufferIDs
			.byPair
			.map!(idpair => idpair[0])
			.reduce!max
		;
		
		auto newClientIDs = iota(maxId+1, maxId+1+count);
		auto newServerIDs = new uint[count];
		glGenBuffers(count, newServerIDs.ptr);
		
		zip(StoppingPolicy.requireSameLength,
			newClientIDs.save, newServerIDs)
			.each!(ids => bufferIDs[ids[0]] = ids[1]);
		return newClientIDs;
		+/
		
		auto newIDs = new uint[count];
		glGenBuffers(count, newIDs.ptr);
		newIDs.each!(id => bufferIDs[id] = id);
		
		tracef("Generated %d new GL buffers: %s", count, newIDs.to!string);
		return newIDs;
	}
	
	/++
	 + Loads a Buffer object, registering its ID and uploading its stored data to the
	 + OpenGL server.
	 +
	 + The buffer should have a currently-unused `clientId` and no `serverId` (i.e. `serverId == 0`)
	++/
	void loadBuffer(Buffer buffer) {
		assert(buffer.serverId == 0, "Tried to load buffer that has a server ID (id is "~buffer.serverId.to!string~")");
		assert(buffer.clientId != 0, "No clientId for buffer.");
		assert(buffer.clientId !in bufferIDs, "clientId already in use.");
		
		// TODO: Proper ID mapping
		buffer.serverId = buffer.clientId;
		buffer.upload();
		bufferIDs[buffer.serverId] = buffer.clientId;
		
		tracef("Loaded GL buffer %d", buffer.clientId);
	}
	
	/// Deletes the passed-in buffers.
	auto deleteBuffers(Range)(Range clientIDs)
	if(isInputRange!Range && is(ElementType!Range : uint)) {
		uint[] serverIDs = clientIDs.map!((id) {
			assert(id in bufferIDs, "tried to delete nonexistant GL buffer: "~to!string(id));
			auto serverID = bufferIDs[id];
			bufferIDs.remove(id);
			return serverID;
		}).array;
		glDeleteBuffers(cast(uint) serverIDs.length, serverIDs.ptr);
		tracef("Deleted %d GL buffers: %s", serverIDs.length, serverIDs.to!string);
	}
	
	/// Deletes all buffers.
	void clearBuffers() {
		auto serverIDs = bufferIDs.byValue.array;
		glDeleteBuffers(cast(uint) serverIDs.length, serverIDs.ptr);
		bufferIDs = typeof(bufferIDs).init;
		assert(bufferIDs.length == 0);
		
		trace("Deleted all GL buffers");
	}
}

unittest {
	static extern(C) void mock_glGenBuffers(int count, uint* buf) nothrow @nogc {
		assert(count == 3);
		assert(buf != null);
		buf[0] = 1;
		buf[1] = 2;
		buf[2] = 3;
	}
	static extern(C) void mock_glDeleteBuffers(int count, const(uint)* buf) nothrow @nogc {
	}
	glGenBuffers = &mock_glGenBuffers;
	glDeleteBuffers = &mock_glDeleteBuffers;
	
	auto idmaps = new IdMaps();
	
	auto clientIDs = idmaps.newBuffers(3);
	assert(clientIDs.equal([1, 2, 3]));
	assert(idmaps.bufferIDs.length == 3);
	assert(idmaps.lookupBuffer(1).get == 1);
	assert(idmaps.lookupBuffer(5).isNull);
	
	idmaps.deleteBuffers([2]);
	assert(idmaps.bufferIDs.length == 2);
	assert(idmaps.lookupBuffer(1).get == 1);
	assert(idmaps.lookupBuffer(2).isNull);
	assert(idmaps.lookupBuffer(3).get == 3);
	
	idmaps.clearBuffers();
	assert(idmaps.bufferIDs.length == 0);
	assert(idmaps.lookupBuffer(1).isNull);
	assert(idmaps.lookupBuffer(2).isNull);
	assert(idmaps.lookupBuffer(3).isNull);
}
