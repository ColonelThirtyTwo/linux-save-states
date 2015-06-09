Linux-Save-States
=================

linux-save-states (LSS) is a work-in-progress tool for performing tool-assisted speed runs of Linux games.

Version 1.0 aims to be compatible with i86 and x86-64 Linux games that use X11 and OpenGL.

Currently status:
-----------------

LSS currently supports the following features:

* Pausing by calling a special `lss_pause` function in the TASed process.
* Saving the process' memory and registers.
* Overriding the process' clocks (by replacing `time (2)` and `clock_gettime (2)`).

Planned features:
-----------------
Roughly in order of priority.

* Inject/replace shared library functions with saveable equivalents (`time`, OpenGL functions, etc)
* OpenGL window creation
* Save states - OpenGL resources
* x11 event injection
* Backwards compatibility with older savestates in new verisons if linux-save-states
* Recording + Replays
* Memory Viewing
* GUI for TASing
* Save states - File contents
* Better support for programs using common libraries (Audio, WINE, Steam, etc)
* Thread support
