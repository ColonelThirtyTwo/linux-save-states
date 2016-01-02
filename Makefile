# Makefile for the injected DLL, shellcode, and test C programs.
# To build the tracer, run `dub build`

TESTPROGS=\
	test-progs/line-cat.exe \
	test-progs/for-loop.exe \
	test-progs/hello-world.exe \
	test-progs/brk.exe \
	test-progs/time.exe \
	test-progs/test-command.exe \
	test-progs/gl/xclient.exe \
	test-progs/gl/buffers.exe \

OBJS = \
	source-c/tracee/tracee.o \
	source-c/tracee/tracee.asm.o \
	source-c/tracee/overrides.o \
	source-c/tracee/x/x.o \
	source-c/tracee/gl/buffer.o \
	source-c/tracee/gl/gl.o \
	source-c/tracee/gl/gl-generated.o \

INJECTED_CFLAGS = -Wall -Wextra -Wno-sign-compare -Os -g -nostdlib -c -I ./resources/ -I ./source-c/tracee -fvisibility=hidden -fno-unwind-tables -fno-asynchronous-unwind-tables -std=gnu99 -fPIC
TEST_CFLAGS = -Wall -Wextra -g -std=gnu99 -L .

all: libsavestates.so $(TESTPROGS)

libsavestates.so: $(OBJS) source-c/tracee/tracee.ld
#	ld -shared -T source-c/tracee/tracee.ld -init init -o $@ $(OBJS) -L /usr/lib/x86_64-linux-gnu/ -ldl
	ld -shared -init init -o $@ $(OBJS) -L /usr/lib/x86_64-linux-gnu/ -ldl

source-c/tracee/tracee.asm.o: source-c/tracee/tracee.x64.S
	nasm -f elf64 -o $@ $<
source-c/tracee/%.o: source-c/tracee/%.c source-c/tracee/gl/gl-generated.c source-c/tracee/gl/gl-generated.h
	gcc $(INJECTED_CFLAGS) -o $@ $<

test-progs/%.exe: source-c/test-progs/%.c libsavestates.so
	gcc -std=gnu99 $(TEST_CFLAGS) -o $@ $+ -l savestates

resources/gl.xml:
	wget -P resources/ -N https://cvs.khronos.org/svn/repos/ogl/trunk/doc/registry/public/api/gl.xml

source-c/tracee/gl/gl-generated.c source-c/tracee/gl/gl-generated.h resources/gl-list.csv: resources/gl.xml gen-gl-wrappers.py
	python3 gen-gl-wrappers.py source-c/tracee/gl/gl-generated.c source-c/tracee/gl/gl-generated.h resources/gl-list.csv < resources/gl.xml

clean:
	rm -f libsavestates.so $(OBJS) test-progs/*.exe source-c/tracee/gl/gl-generated.c source-c/tracee/gl/gl-generated.h resources/gl-list.csv

clean-all: clean
	rm -f resources/gl.xml

.PHONY: all clean clean-all .FORCE
