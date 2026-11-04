# Sega Saturn for the Analogue Pocket

An openFPGA core that plays Sega Saturn games on the Analogue Pocket. It is a port of the MiSTer Saturn core,
[Saturn_MiSTer](https://github.com/MiSTer-devel/Saturn_MiSTer) by Sergiy Dvodnenko (srg320) and contributors,
trimmed to fit the Pocket's Cyclone V FPGA and adapted to the Pocket's memories and the Analogue Pocket Framework.

## Licenses

This repository is distributed under the GNU General Public License, version 3 or (at your option) any later
version: see `LICENSE`. Files from other projects keep their own notices:

| Path | From | License |
|---|---|---|
| `src/fpga/rtl` | Saturn_MiSTer (commit 9aa9449, 2026-10-19), modified | as upstream (upstream has no license file) |
| `src/fpga/rtl/FX68K` | fx68k by Jorge Cwik, modified | GPL-3.0-or-later |
| `src/fpga/rtl/Saturn/CD/femtorv` | FemtoRV32 by Bruno Levy and Matthias Koch | BSD-3-Clause (`LICENSE` there) |
| `src/fpga/rtl/Saturn/CD/picorv32.v` | PicoRV32 by Claire Xenia Wolf | ISC (in the file) |
| `src/fw/cdb/cdb_hle.c` | Mednafen's CD block emulation (Mednafen Team), adapted | GPL-2.0-or-later |
| `src/fpga/apf` | Analogue Pocket Framework (Analogue); Intel / Altera generated files | as in each file |
| `src/fpga/core/core_top.v`, `core_bridge_cmd.v` | Analogue's openFPGA core template, modified | as the template |
| `src/fpga/core/sound_i2s.sv`, `sync_fifo.sv` | Adam Gastineau | MIT (in the files) |
| `dist/Platforms/_images/saturn.bin`, `dist/Cores/akoaysigod.Saturn/icon.bin` | photo of a Saturn by Evan-Amos, [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Sega-Saturn-Console-Set-Mk1.jpg), converted with `tools/png2pocket.py` | public domain |
| everything else | this project (akoaysigod) | GPL-3.0-or-later |

Sega Saturn is a trademark of Sega. This project is not affiliated with Sega, Analogue or the MiSTer project.
