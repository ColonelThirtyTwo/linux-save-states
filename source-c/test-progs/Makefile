
all: hello-world.exe for-loop.exe

%.exe: %.c
	gcc -std=gnu99 -Wall -g -o $@ $<

%.exe.nolib: %.c
	gcc -std=gnu99 -Wall -nostartfiles -nostdlib -g -o $@ $<

%.bin: %.S
	nasm -f bin -o $@ $<

clean:
	rm -f *.exe *.exe.nolib

.PHONY: all clean
