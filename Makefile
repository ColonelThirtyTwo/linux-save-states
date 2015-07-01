# Makefile for the injected DLL, shellcode, and test C programs.
# To build the tracer, run `dub build`

TESTPROGS=\
	test-progs/line-cat.exe \
	test-progs/for-loop.exe \
	test-progs/hello-world.exe \
	test-progs/brk.exe \
	test-progs/time.exe \
	test-progs/test-command.exe \
	test-progs/xclient.exe \

OBJS = \
	source-c/tracee/tracee.o \
	source-c/tracee/tracee.asm.o \
	source-c/tracee/overrides.o \
	source-c/tracee/x/x.o \

CFLAGS = -Wall -Os -g -nostdlib -c -I ./resources/ -I ./source-c/tracee -fvisibility=hidden -fno-unwind-tables -fno-asynchronous-unwind-tables -std=gnu99 -fPIC

all: libsavestates.so $(TESTPROGS)

libsavestates.so: $(OBJS) source-c/tracee/tracee.ld
	ld -shared -T source-c/tracee/tracee.ld -init init -o $@ $(OBJS) -L /usr/lib/x86_64-linux-gnu/ -ldl

source-c/tracee/tracee.o: source-c/tracee/tracee.c
	gcc $(CFLAGS) -o $@ $<
source-c/tracee/tracee.asm.o: source-c/tracee/tracee.x64.S
	nasm -f elf64 -o $@ $<
source-c/tracee/overrides.o: source-c/tracee/overrides.c
	gcc $(CFLAGS) -o $@ $<
source-c/tracee/x/x.o: source-c/tracee/x/x.c
	gcc $(CFLAGS) -o $@ $<

source-c/tracee/gl/gl.o: source-c/tracee/gl/gl.generated.c source-c/tracee/gl/glcompsizes.h
	gcc $(CFLAGS) -o $@ $<
source-c/tracee/gl/gl.generated.c: source-c/tracee/gl/gl.xml ./gen-gl-wrappers.py
	python3 ./gen-gl-wrappers.py source/gl.d $@ < $<
source-c/tracee/gl/gl.xml:
	curl -sSf -z $@ -o $@ https://cvs.khronos.org/svn/repos/ogl/trunk/doc/registry/public/api/gl.xml

test-progs/%.exe: source-c/test-progs/%.c libsavestates.so
	gcc -std=gnu99 -Wall -L . -g -o $@ $+ -l savestates
test-progs/xclient.exe: source-c/test-progs/xclient.c libsavestates.so
	gcc -std=gnu99 -Wall -L . -g -o $@ $+ -l X11 -l savestates

clean:
	rm -f libsavestates.so $(OBJS) test-progs/*.exe

.PHONY: all clean .FORCE
