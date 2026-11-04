// SMPC firmware (SMPC_FW builds): the SMPC's MCU program runs here, beside the CD block code, on SMPC_FW.sv's
// registers (I/O words 0x80-0xFF). The CD code calls smpc_poll() often (its main loop and its long loops).
#pragma once
#include <stdint.h>
#include <stdbool.h>

void smpc_init(void);           // after RST_N (the CPU's reset): the MCU from its reset state
void smpc_poll(void);           // run the MCU program up to the present when it can make progress
bool smpc_cd_released(void);    // CDRES_N (the SMPC's CD block reset) is high
extern bool cd_running;         // the CD code runs (not held in reset)
// the CD code's next deadline: while the drive plays, its next event (IO_TIMER ticks, 11.2896 MHz): the CD-DA queue
// holds one sector and a few samples, so the SMPC keeps out of the way around it (smpc_world.c poll_run)
extern uint32_t smpc_cd_deadline;
extern bool smpc_cd_deadline_on;
void cd_restart(void) __attribute__((noreturn));   // the CD code from its start (cdb_hle.c), on a fresh stack
