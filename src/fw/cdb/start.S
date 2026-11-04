# CD block HLE firmware start: stack, .bss cleared (also after a CD block reset), main.
	.section .text.start
	.globl _start
_start:
	la sp, __stack_top
#ifdef SMPC_FW
	/* the SMPC's data (link_smpc.ld); the CD block's part is cleared by cd_restart() */
	.option push
	.option norelax
	la gp, __global_pointer$
	.option pop
	la a0, __smpc_bss_start
	la a1, __smpc_bss_end
#else
	la a0, __bss_start
	la a1, __bss_end
#endif
1:	bgeu a0, a1, 2f
	sw zero, 0(a0)
	addi a0, a0, 4
	j 1b
2:	call main
3:	j 3b
#ifdef SMPC_FW
/* SMPC_FW: the CD part of the firmware from its start (cd_restart in cdb_hle.c), on a fresh stack: entered from
   smpc_poll() when the SMPC holds the CD block in reset (CDRES_N low). */
	.section .text.cd_restart_entry
	.globl cd_restart_entry
cd_restart_entry:
	la sp, __stack_top
	j cd_restart
#endif
