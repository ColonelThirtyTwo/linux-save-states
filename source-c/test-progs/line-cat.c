
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <unistd.h>

void lss_pause();

int main(int argc, char** argv) {
	if(argc != 2) {
		fprintf(stderr, "Usage: line-cat file\n");
		return 1;
	}
	
	printf("PID: %d\n", getpid());
	
	FILE* f = fopen(argv[1], "rb");
	if(!f) {
		fprintf(stderr, "Couldn't open: %s\n", strerror(errno));
		return 2;
	}
	
	int c;
	while((c = fgetc(f)) != EOF) {
		fputc((unsigned char) c, stdout);
		
		if(c == '\n')
			lss_pause();
	}
	
	fclose(f);
	return 0;
}
