
SECTIONS {
	. = 0x0;
	.text . : {
		source-c/injection/injection.o(.text)
		. = 0x090900;
		source-c/injection/injection.asm.o(.text)
		. = 0x100000;
		
		FILL(0x0);
	}
	
	.data . : {
		injectionData = .;
		QUAD(0)
		
		source-c/injection/injection.o(.data)
		. = 0x100500;
		
		FILL(0x0);
	}
	
	.rodata . : {
		*(.rodata)
		. = 0x101000;
		
		FILL(0x0);
	}
}
