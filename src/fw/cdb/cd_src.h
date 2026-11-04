// glue/cd design B: the Pocket's disc source in the CD block firmware (cd_src.c): the TOC from the data slots (the
// .cue, or by convention), sectors through a ring of APF data slot reads with read-ahead and seek hints.
#pragma once
#include "hw.h"
#include "rt.h"

void src_power_on(void);                     // the CPU's power-on: forget the disc (scanned again)
void src_init(void);                         // the CD code starts: scan the data slots unless done
void src_poll(void);                         // often: the scan, finished reads, read-ahead, the drive's request
bool src_toc(TOC* toc);                      // the TOC (false: no disc)
unsigned src_read(int32_t lba, unsigned pf); // the drive reads lba (FAD - 150) into page pf[7:0], pf[8]: data;
                                             // returns the page that holds / will hold it (CD_SRC_L2: a spare page
                                             // already holding it takes the drive's place, the drive's page goes spare)
bool src_pending(void);                      // that read is not in the sector engine yet
void src_cancel(void);                       // the drive dropped it (not started yet: forget it)
void src_hint(int32_t lba);                  // the drive will read from lba (seek start): fetch it now
