
module bindings.libevent;

import std.stdio;
import std.exception;
import std.traits;
import std.string : fromStringz;
import std.container.dlist;
import std.variant;
import core.stdc.stdlib;

public import deimos.event2.event;
import deimos.event2.thread;

private extern(C) nothrow void logCb(int severity, const(char)* msg) {
	assumeWontThrow(writeln("LibEvent: "~msg.fromStringz()));
}

/// Initializes libevent.
void initEvents() {
	debug event_enable_debug_mode();
	evthread_use_pthreads();
	
	event_set_log_callback(&logCb);
}

struct EventSource {
	private {
		Events owner;
		event* handle;
	}
	
	/// Manually triggers an event.
	/// This is the only way to trigger custom events.
	void trigger(short flags=0) {
		event_active(handle, flags, 0);
	}
}



static struct FileEvent {
	EventSource* source;
	int fd;
	bool readable;
	bool writeable;
}

static struct SignalEvent {
	EventSource* source;
	int signal;
}

static struct CustomEvent {
	EventSource* source;
}

alias Event = Algebraic!(FileEvent, SignalEvent, CustomEvent);


/**
 * High level interface for libevent.
 * This exposes a queue API, instead of libevent's callback API, because throwing exceptions in a
 * libevent callback will segfault.
**/
final class Events {
	private {
		event_base* base;
		EventSource*[] events;
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
			event_del(ud.handle);
			event_free(ud.handle);
			free(ud);
		}
		events = null;
		
		if(base != null) {
			event_base_free(base);
			base = null;
		}
	}
	
	private static {
		extern(C) void fileEventCb(int fd, short flags, void* ud) {
			auto data = cast(EventSource*) ud;
			
			data.owner.queue.insertBack(Event(FileEvent(
				data,
				fd, 
				(flags & EV_READ) != 0,
				(flags & EV_WRITE) != 0
			)));
		}
		
		extern(C) void signalEventCb(int sig, short flags, void* ud) {
			auto data = cast(EventSource*) ud;
			
			assert(flags == EV_SIGNAL);
			data.owner.queue.insertBack(Event(SignalEvent(data, sig)));
		}
		
		extern(C) void customEventCb(int fd, short flags, void* ud) {
			auto data = cast(EventSource*) ud;
			
			assert(flags == EV_SIGNAL);
			data.owner.queue.insertBack(Event(CustomEvent(data)));
		}
	}
	
	private EventSource* add(int fd, short flags, event_callback_fn cb) {
		auto src = cast(EventSource*) malloc(EventSource.sizeof);
		src.owner = this;
		auto ev = event_new(base, fd, flags, cb, src);
		enforce(ev != null);
		enforce(event_add(ev, null) == 0);
		src.handle = ev;
		events ~= src;
		return src;
	}
	
	/// Begins listening for file read/write-ability.
	EventSource* addFile(int fd, bool onReadable=true, bool onWriteable=false) {
		return this.add(fd,
			(onReadable ? EV_READ : 0) |
			(onWriteable ? EV_WRITE : 0) |
			EV_PERSIST,
			&fileEventCb
		);
	}
	
	/// Begins listineng for a signal
	EventSource* addSignal(int signal) {
		return this.add(signal, EV_SIGNAL | EV_PERSIST, &signalEventCb);
	}
	
	/// Begins listening for a custom event, which can only be triggered via `event.trigger()`
	EventSource* addCustom() {
		return this.add(0, EV_PERSIST, &customEventCb);
	}
	
	/**
	 * Gets an event from the queue.
	 *
	 * If block is true, wait for at least one event.
	**/
	Event next(bool block=true) @property {
		if(queue.empty && block) {
			enforce(event_base_loop(base, EVLOOP_ONCE) != -1);
		}
		if(queue.empty)
			return Event();
		
		auto front = queue.front;
		queue.removeFront();
		return front;
	}
}
