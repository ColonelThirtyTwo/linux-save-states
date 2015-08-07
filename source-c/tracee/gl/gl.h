
#ifndef _LSS_GL
#define _LSS_GL

void initGlBuffer(void);
void queueGlCommand(const void* cmd, size_t len);
void flushGlBuffer(void);

#endif
