
The tracer injects this library (using `LD_PRELOAD`) into the tracee process.

Editing considerations
----------------------

Save states are fragile; they require that the process loads the exact same code that it did when the state was saved.
Even minor changes to the source code can cause symbols to wind up in completely different places. This includes the
code injected by linux-save-states.

For TASing, it's not too inconvenient to disable updates for the traced program while recording, as the traced program
is likely stable. However, the same cannot be said for linux-save-states itself. It would be incredibly inconvenient
to find a bug in linux-save-states halfway throughout a TAS, and have to restart the entire TAS because the bugfix
causes save states to fail to load.

To mitigate this problem, we use a special linker script in order to pad the code area of the injected code, so that it
can grow (by filling the padding) without changing the size of the memory usage of the program. We also write the code
that the process is saved at in assembly, and locate it in a fixed point in the shared library.

Keep in mind the following points when editing the files:

* No top-level variables should be declared. All data should be stored in the `traceeData` struct.
* Changes to tracee.*.S will likely be incompatible with older versions.
* To minimize bloat, libc is not linked in, so no standard functions.
* All symbols are hidden by default (via the -fvisibility flag).
