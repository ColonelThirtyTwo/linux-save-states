/// Global variables
module global;

import savefile;
import procinfo;

/// Handle of the save file
SaveStatesFile saveFile;

/// The proceess currently being traced, or null if not tracing anything right now.
ProcInfo process;
