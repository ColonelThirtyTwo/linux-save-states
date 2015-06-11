# Makefile for the injected DLL, shellcode, and test C programs.
# To build the tracer, run `dub build`

TESTPROGS=\
	test-progs/line-cat.exe \
	test-progs/for-loop.exe \
	test-progs/hello-world.exe \
	test-progs/brk.exe \
	test-progs/time.exe \

OBJS = \
	source-c/tracee/tracee.o \
	source-c/tracee/tracee.asm.o \
	source-c/tracee/overrides.o \

CFLAGS = -Wall -Os -g -nostdlib -c -I ./resources/ -fvisibility=hidden -fno-unwind-tables -fno-asynchronous-unwind-tables -std=gnu99 -fPIC

all: libsavestates.so $(TESTPROGS)

libsavestates.so: $(OBJS) source-c/tracee/tracee.ld
	ld -shared -T source-c/tracee/tracee.ld -init init -o $@ $(OBJS)

source-c/tracee/tracee.o: source-c/tracee/tracee.c
	gcc $(CFLAGS) -o $@ $<
source-c/tracee/tracee.asm.o: source-c/tracee/tracee.x64.S
	nasm -f elf64 -o $@ $<
source-c/tracee/overrides.o: source-c/tracee/overrides.c
	gcc $(CFLAGS) -o $@ $<

source-c/tracee/gl.o: source-c/tracee/gl.generated.c source-c/tracee/glcompsizes.h
	gcc $(CFLAGS) -o $@ $<
source-c/tracee/gl.generated.c: source-c/tracee/gl.xml ./gen-gl-wrappers.py
	python3 ./gen-gl-wrappers.py source/gl.d $@ < $<
source-c/tracee/gl.xml:
	curl -sSf -z $@ -o $@ https://cvs.khronos.org/svn/repos/ogl/trunk/doc/registry/public/api/gl.xml

test-progs/%.exe: source-c/test-progs/%.c libsavestates.so
	gcc -std=gnu99 -Wall -L . -g -o $@ $+ -l savestates

clean:
	rm -f libsavestates.so source-c/tracee/*.o test-progs/*.exe

.PHONY: all clean .FORCE
