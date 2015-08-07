
#ifndef _LSS_GL_BUFFER
#define _LSS_GL_BUFFER

void initGlBuffer(void);
void queueGlCommand(const void* cmd, size_t len);
void flushGlBuffer(void);

#endif
