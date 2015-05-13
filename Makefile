# Makefile for the injected DLL, shellcode, and test C programs.
# To build the tracer, run `dub build`

all: libsavestates.so test-progs/line-cat.exe test-progs/for-loop.exe test-progs/hello-world.exe

libsavestates.so: source-c/injection/injection.c
	gcc -Wall -I ./resources/ -std=gnu99 -shared -g -fPIC -o $@ $<

test-progs/%.exe: source-c/test-progs/%.c libsavestates.so
	gcc -std=gnu99 -Wall -L . -g -o $@ $< -l savestates

clean:
	rm -f libsavestates.so test-progs/*.exe

.PHONY: all clean
