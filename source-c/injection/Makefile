
libsavestates.so: injection.c
	gcc -Wall -I ../../resources/ -std=gnu99 -shared -g -fPIC -o $@ $<

clean:
	rm -f libsavestates.so

.PHONY: clean
