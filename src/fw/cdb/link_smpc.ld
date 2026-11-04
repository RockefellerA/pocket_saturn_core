/* CD block HLE firmware with the SMPC (SMPC_FW): one RAM at 0. The CD block part first (code, read-only data, .bss:
   its raw transfers (TOC, subcode, file info) give the hardware a 16-bit CPU RAM byte address, so its data must stay
   below 64 KB), then the SMPC part (code, read-only data, .bss), .noinit (kept across RST_N), the stack at the top.
   A CD block reset clears only the CD part's .bss (__cd_bss_start .. __cd_bss_end); the SMPC's is cleared at RST_N.
   The global pointer addresses the SMPC's data (linked with --relax-gp: only the SMPC's variables are within its
   +-2 KB, the CD block code is not changed by it). No initialised .data (build.sh checks). LENGTH: build.sh sets it
   from WORDS. */
MEMORY { RAM (rwx) : ORIGIN = 0, LENGTH = 80K }
SECTIONS
{
	.text : { KEEP(*(.text.start)) *(EXCLUDE_FILE(*smpc_*.o) .text EXCLUDE_FILE(*smpc_*.o) .text.*) } > RAM
	.rodata : { *(EXCLUDE_FILE(*smpc_*.o) .rodata EXCLUDE_FILE(*smpc_*.o) .rodata.* EXCLUDE_FILE(*smpc_*.o) .srodata
	            EXCLUDE_FILE(*smpc_*.o) .srodata.*) . = ALIGN(4); } > RAM
	.data : { *(.data .data.* .sdata .sdata.*) } > RAM
	.bss (NOLOAD) : {
		. = ALIGN(4); __cd_bss_start = .;
		*(EXCLUDE_FILE(*smpc_*.o) .bss EXCLUDE_FILE(*smpc_*.o) .bss.* EXCLUDE_FILE(*smpc_*.o) .sbss
		  EXCLUDE_FILE(*smpc_*.o) .sbss.* EXCLUDE_FILE(*smpc_*.o) COMMON)
		. = ALIGN(4); __cd_bss_end = .;
	} > RAM
	.smpc_text : { *smpc_*.o(.text .text.*) } > RAM
	.smpc_rodata : { *smpc_*.o(.rodata .rodata.* .srodata .srodata.*) . = ALIGN(4); } > RAM
	.smpc_bss (NOLOAD) : {
		. = ALIGN(4); __smpc_bss_start = .;
		*smpc_*.o(.bss .bss.* .sbss .sbss.* COMMON)
		. = ALIGN(4); __smpc_bss_end = .;
	} > RAM
	.noinit (NOLOAD) : { *(.noinit) . = ALIGN(4); } > RAM
	__global_pointer$ = __smpc_bss_start + 0x800;
	__stack_top = ORIGIN(RAM) + LENGTH(RAM);
	ASSERT(__cd_bss_end <= 0x10000, "the CD block's data must be below 64 KB (raw transfers)")
	/DISCARD/ : { *(.comment) *(.riscv.attributes) *(.note*) }
}
