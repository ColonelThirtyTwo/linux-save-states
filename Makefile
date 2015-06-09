# Makefile for the injected DLL, shellcode, and test C programs.
# To build the tracer, run `dub build`

TESTPROGS=\
	test-progs/line-cat.exe \
	test-progs/for-loop.exe \
	test-progs/hello-world.exe \
	test-progs/brk.exe \
	test-progs/time.exe \

OBJS = \
	source-c/injection/injection.o \
	source-c/injection/injection.asm.o \
	source-c/injection/overrides.o \

CFLAGS = -Wall -Os -g -nostdlib -c -I ./resources/ -fvisibility=hidden -fno-unwind-tables -fno-asynchronous-unwind-tables -std=gnu99 -fPIC

all: libsavestates.so $(TESTPROGS)

libsavestates.so: $(OBJS) source-c/injection/injection.ld
	ld -shared -T source-c/injection/injection.ld -init init -o $@ $(OBJS)

source-c/injection/injection.o: source-c/injection/injection.c
	gcc $(CFLAGS) -o $@ $+
source-c/injection/injection.asm.o: source-c/injection/injection.x64.S
	nasm -f elf64 -o $@ $+
source-c/injection/overrides.o: source-c/injection/overrides.c
	gcc $(CFLAGS) -o $@ $+

test-progs/%.exe: source-c/test-progs/%.c libsavestates.so
	gcc -std=gnu99 -Wall -L . -g -o $@ $+ -l savestates

clean:
	rm -f libsavestates.so source-c/injection/*.o test-progs/*.exe

.PHONY: all clean
