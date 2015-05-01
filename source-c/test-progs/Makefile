
all: hello-world.exe for-loop.exe

%.exe: %.c libsavestates.so
	gcc -std=gnu99 -Wall -L . -g -o $@ $< -l savestates

%.exe.nolib: %.c
	gcc -std=gnu99 -Wall -nostartfiles -nostdlib -g -o $@ $<

%.bin: %.S
	nasm -f bin -o $@ $<

libsavestates.so: ../injection/libsavestates.so
	cp $< $@

clean:
	rm -f *.exe *.exe.nolib *.bin *.so

.PHONY: all clean
