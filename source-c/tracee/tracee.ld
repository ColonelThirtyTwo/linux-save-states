
SECTIONS {
	.text 0x0 : {
		_begin_text = .;
		
		source-c/tracee/tracee.o(.text*)
		source-c/tracee/overrides.o(.text*)
		source-c/tracee/x/x.o(.text*)
		. = 0x090900;
		
		source-c/tracee/tracee.asm.o(.text)
		. = 0x100000;
		
		_end_text = .;
		FILL(0x0);
	}
	
	.data 0x101000 : {
		_begin_data = .;
		
		*(.data)
		*(.bss)
		. = 0x000500;
		
		_end_data = .;
		FILL(0x0);
	}
	
	.rodata 0x102000 : {
		_begin_rodata = .;
		
		*(.rodata)
		*(.rodata*)
		. = 0x010000;
		
		_end_rodata = .;
		FILL(0x0);
	}
}
