/* CD block HLE firmware: one RAM at 0: code, read-only data, .bss, stack. No initialised .data (build.sh checks):
   a CD block reset restarts the firmware with the RAM as the last run left it. */
MEMORY { RAM (rwx) : ORIGIN = 0, LENGTH = 40K }
SECTIONS
{
	.text : { KEEP(*(.text.start)) *(.text .text.*) } > RAM
	.rodata : { *(.rodata .rodata.* .srodata .srodata.*) . = ALIGN(4); } > RAM
	.data : { *(.data .data.* .sdata .sdata.*) } > RAM
	.bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.bss .bss.* .sbss .sbss.* COMMON) . = ALIGN(4); __bss_end = .; } > RAM
	.noinit (NOLOAD) : { *(.noinit) . = ALIGN(4); } > RAM	/* (CD_SRC_FW: cd_src.c's disc layout; not in the image) */
	__stack_top = ORIGIN(RAM) + LENGTH(RAM);
	/DISCARD/ : { *(.comment) *(.riscv.attributes) *(.note*) }
}
