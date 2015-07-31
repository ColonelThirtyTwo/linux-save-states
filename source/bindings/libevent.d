
module bindings.libevent;

import std.stdio;
import std.exception;
import std.traits;
import std.string : fromStringz;
import std.container.dlist;
import std.variant;
import core.memory;

public import deimos.event2.event;
import deimos.event2.thread;

private extern(C) nothrow void logCb(int severity, const(char)* msg) {
	assumeWontThrow(writeln("LibEvent: "~msg.fromStringz()));
}

void initEvents() {
	debug event_enable_debug_mode();
	evthread_use_pthreads();
	
	event_set_log_callback(&logCb);
}



static struct FileEvent {
	int fd;
	bool readable;
	bool writeable;
}

static struct SignalEvent {
	int signal;
}

static struct CustomEvent {
	void* handler;
}

alias Event = Algebraic!(FileEvent, SignalEvent, CustomEvent);



final class Events {
	private {
		event_base* base;
		EventUserData*[] events;
		DList!Event queue;
	}
	
	this() {
		auto config = event_config_new();
		enforce(config != null);
		scope(exit) event_config_free(config);
		
		event_config_require_features(config, event_method_feature.EV_FEATURE_FDS);
		
		base = event_base_new_with_config(config);
		enforce(base != null);
	}
	
	~this() {
		foreach(ud; events) {
			event_del(ud.handler);
			event_free(ud.handler);
			unpin(ud);
		}
		events = null;
		
		if(base != null) {
			event_base_free(base);
			base = null;
		}
	}
	
	private static {
		T* pin(T)(T* ptr) {
			GC.addRoot(cast(void*)ptr);
			GC.setAttr(cast(void*)ptr, GC.BlkAttr.NO_MOVE);
			return ptr;
		}
		T* unpin(T)(T* ptr) {
			GC.removeRoot(cast(void*)ptr);
			GC.clrAttr(cast(void*)ptr, GC.BlkAttr.NO_MOVE);
			return ptr;
		}
		
		struct EventUserData {
			Events events;
			event* handler;
		}
		
		extern(C) void fileEventCb(int fd, short flags, void* ud) {
			auto data = cast(EventUserData*) ud;
			
			assumeWontThrow(writeln("file event"));
			
			data.events.queue.insertBack(Event(FileEvent(fd, 
				(flags & EV_READ) != 0,
				(flags & EV_WRITE) != 0
			)));
		}
		
		extern(C) void signalEventCb(int sig, short flags, void* ud) {
			auto data = cast(EventUserData*) ud;
			
			assumeWontThrow(writeln("signal event"));
			
			assert(flags == EV_SIGNAL);
			data.events.queue.insertBack(Event(SignalEvent(sig)));
		}
		
		extern(C) void customEventCb(int fd, short flags, void* ud) {
			auto data = cast(EventUserData*) ud;
			
			assumeWontThrow(writeln("custom event"));
			
			assert(flags == EV_SIGNAL);
			data.events.queue.insertBack(Event(CustomEvent(cast(void*)data.handler)));
		}
	}
	
	void addFile(int fd, bool onReadable=true, bool onWriteable=false) {
		auto ud = pin(new EventUserData(this, null));
		auto ev = event_new(base, fd, 
			(onReadable ? EV_READ : 0) |
			(onWriteable ? EV_WRITE : 0) |
			EV_PERSIST,
			&fileEventCb, ud
		);
		enforce(ev != null);
		enforce(event_add(ev, null) == 0);
		ud.handler = ev;
		events ~= ud;
	}
	
	void addSignal(int signal) {
		auto ud = pin(new EventUserData(this, null));
		auto ev = event_new(base, signal, EV_SIGNAL | EV_PERSIST, &signalEventCb, ud);
		enforce(ev != null);
		enforce(event_add(ev, null) == 0);
		ud.handler = ev;
		events ~= ud;
	}
	
	void* addCustom() {
		auto ud = pin(new EventUserData(this, null));
		auto ev = event_new(base, 0, EV_PERSIST, &customEventCb, ud);
		enforce(ev != null);
		enforce(event_add(ev, null) == 0);
		ud.handler = ev;
		events ~= ud;
		
		return cast(void*) ev;
	}
	
	Event next() @property {
		if(queue.empty) {
			enforce(event_base_loop(base, EVLOOP_ONCE) != -1);
			if(queue.empty)
				return Event();
		}
		
		auto front = queue.front;
		queue.removeFront();
		return front;
	}
	
	/+void addFileEvent(int fd, EventCallback callback, bool onReadable=true, bool onWriteable=false) {
		auto ev = event_new(base, fd, 
			(onReadable ? EV_READ : 0) |
			(onWriteable ? EV_WRITE : 0) |
			EV_PERSIST,
			&eventCb, pin(new EventData(callback))
		);
		enforce(ev != null);
		enforce(event_add(ev, null) == 0);
		events ~= ev;
	}
	
	void addSignalEvent(int signal, EventCallback callback) {
		auto ev = event_new(base, signal, EV_SIGNAL | EV_PERSIST, &eventCb, pin(new EventData(callback)));
		enforce(ev != null);
		enforce(event_add(ev, null) == 0);
		events ~= ev;
	}
	
	void delegate(int) addCustomEvent(EventCallback callback) {
		auto ev = event_new(base, 0, EV_PERSIST, &eventCb, pin(new EventData(callback)));
		enforce(ev != null);
		enforce(event_add(ev, null) == 0);
		events ~= ev;
		return (int flags) { event_active(ev, flags, 0); };
	}
	
	void exitLoop() {
		enforce(event_base_loopexit(base, null) == 0);
	}
	
	void dispatch() {
		enforce(event_base_dispatch(base) != -1);
	}+/
}
