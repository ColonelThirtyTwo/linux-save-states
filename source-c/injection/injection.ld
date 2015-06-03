
SECTIONS {
	.text 0x0 : {
		_begin_text = .;
		
		source-c/injection/injection.o(.text)
		. = 0x090900;
		source-c/injection/injection.asm.o(.text)
		. = 0x100000;
		
		_end_text = .;
		FILL(0x0);
	}
	
	.data 0x100000 : {
		_begin_data = .;
		
		injectionData = .;
		QUAD(0)
		
		*(.data)
		. = 0x000500;
		
		_end_data = .;
		FILL(0x0);
	}
	
	/* Leave some space for .dynamic */
	.rodata 0x101000 : {
		_begin_rodata = .;
		
		*(.rodata)
		*(.rodata*)
		. = 0x010000;
		
		_end_rodata = .;
		FILL(0x0);
	}
}
