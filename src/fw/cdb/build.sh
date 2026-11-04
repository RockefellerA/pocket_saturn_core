#!/bin/sh
# Build the CD block HLE firmware: clang (RV32I) + rust-lld (in the rust:1.88 image) -> cdb_hle.elf, and the RAM
# image for CDB_HLE.sv ($readmemh, one 32-bit word per line, RAM_WORDS lines) into the RTL tree (src/fpga/rtl).
# Tools: LLVM = the directory of clang, llvm-objcopy and llvm-size (default Homebrew's); LD_LLD = a local ld.lld to
# link with instead of rust-lld in Docker.
# SMPC_FW=1: with the SMPC's MCU program (smpc_*.c, for rtl/Saturn/SMPC/SMPC_FW.sv): link_smpc.ld, 80 KB RAM,
# cdb_hle_smpc_fw.hex. The program is generated from the SMPC ROM (MIF, default the RTL tree's smpc.mif).
# CD_SRC=1: with the Pocket's disc source (cd_src.c: APF data slots, the .cue, read-ahead, seek hints; for CDB_HLE's EXT
# port, RTL macro CD_EXTIO; glue/cd/REPORT.txt design B2); CD_SRC_L2=0 leaves out its second read-ahead level (spare CD
# RAM pages). SMPC_FW=1 CD_SRC=1 is the Pocket's image: 88 KB in CDB_HLE's two RAM banks (WORDS 22528, BANK0 20480),
# cdb_hle_pocket_fw.hex + cdb_hle_pocket_fw_1.hex. CD_SRC=1 alone (the benches' 40 KB image) needs OUT.
# BANK0=n (< WORDS): two image files for the two-bank RAM: OUT = words 0 .. n - 1, OUT minus .hex + _1.hex = the rest.
# DEFS: more C defines (experiments). Without CD_SRC / BANK0 / DEFS the images are the ones built before these options.
set -e
H=$(cd "$(dirname "$0")" && pwd)
RTL=$(cd "$H/../../fpga/rtl" && pwd)
LLVM=${LLVM:-/opt/homebrew/opt/llvm/bin}
CL=$LLVM/clang
XS=
if [ -n "$CD_SRC" ]; then
  XS=" cd_src"
  DEFS="$DEFS -DCD_SRC_FW"; [ "${CD_SRC_L2:-1}" = 0 ] || DEFS="$DEFS -DCD_SRC_L2"
fi
CF="$DEFS --target=riscv32-unknown-elf -march=rv32i -mabi=ilp32 -ffreestanding -fno-builtin -Os -ffunction-sections -fdata-sections -Wall -Wno-unused-function -Wno-unused-but-set-global"
SRCS="cdb_hle rt$XS"
LDS=link.ld
SF=
if [ -n "$SMPC_FW" ]; then
  if [ -n "$CD_SRC" ]; then
    WORDS=${WORDS:-22528}; BANK0=${BANK0:-20480}
    OUT=${OUT:-$RTL/Saturn/CD/cdb_hle_pocket_fw.hex}
  fi
  WORDS=${WORDS:-20480}
  OUT=${OUT:-$RTL/Saturn/CD/cdb_hle_smpc_fw.hex}
  SRCS="cdb_hle rt$XS smpc_fw obj/smpc_mcu_gen"
  LDS=link_smpc.ld
  SF="-DSMPC_FW $SMPC_DEFS"   # (SMPC_DEFS: experiments, e.g. -DMCU_RUN_CAP=64 -DSMPC_POLL_BUDGET=64)
  # the SMPC's MCU program, translated from its ROM (MIF: the RTL tree's smpc.mif) by smpc_gen/gen_mcu.py
  MIF=${MIF:-$RTL/Saturn/SMPC/smpc.mif}
  [ -f "$MIF" ] || { echo "SMPC ROM not found: $MIF (set MIF)"; exit 1; }
  mkdir -p "$H/obj"
  python3 -I "$H/smpc_gen/gen_mcu.py" "$MIF" "$H/smpc_gen/idecode_dump.txt" "$H/obj/smpc_mcu_gen.c" 0
fi
[ -n "$CD_SRC" ] && [ -z "$OUT" ] && { echo "CD_SRC without SMPC_FW (a bench image): set OUT"; exit 1; }
WORDS=${WORDS:-10240}
OUT=${OUT:-$RTL/Saturn/CD/cdb_hle_fw.hex}
mkdir -p "$H/obj"
OBJS=""
for f in $SRCS; do
  X=""; [ "$f" = obj/smpc_mcu_gen ] && X="-Wno-unused-label -I$H"
  [ "$f" = smpc_fw ] && X="${SMPC_OPT:--Os}"     # the SMPC runtime: speed (the CD block code and the program: -Os)
  o=obj/$(basename $f).o
  $CL $CF $SF $X -c "$H/$f.c" -o "$H/$o"
  OBJS="$OBJS $o"
done
$CL --target=riscv32-unknown-elf -march=rv32i -mabi=ilp32 $SF -c "$H/start.S" -o "$H/obj/start.o"
LLD=/usr/local/rustup/toolchains/1.88.0-aarch64-unknown-linux-gnu/lib/rustlib/aarch64-unknown-linux-gnu/bin/rust-lld
if [ -n "$SMPC_FW" ]; then   # the RAM size in the linker script follows WORDS
  sed "s/LENGTH = 80K/LENGTH = $((WORDS * 4))/" "$H/link_smpc.ld" > "$H/obj/link_smpc.ld"; LDS="obj/link_smpc.ld --relax-gp"
fi
if [ -n "$LD_LLD" ]; then
  (cd "$H" && $LD_LLD -m elf32lriscv --gc-sections -T $LDS -o obj/cdb_hle.elf obj/start.o $OBJS -Map obj/cdb_hle.map)
else
# (retried once: right after another build, Docker's file share can still miss the new objects)
docker run --rm -v "$H:/fw" -w /fw rust:1.88 $LLD -flavor gnu -m elf32lriscv --gc-sections -T $LDS \
  -o obj/cdb_hle.elf obj/start.o $OBJS -Map obj/cdb_hle.map || { sleep 3; \
docker run --rm -v "$H:/fw" -w /fw rust:1.88 $LLD -flavor gnu -m elf32lriscv --gc-sections -T $LDS \
  -o obj/cdb_hle.elf obj/start.o $OBJS -Map obj/cdb_hle.map; }
fi
$LLVM/llvm-objcopy -O binary obj/cdb_hle.elf obj/cdb_hle.bin 2>/dev/null || \
  $LLVM/llvm-objcopy -O binary "$H/obj/cdb_hle.elf" "$H/obj/cdb_hle.bin"
python3 -I - "$H/obj/cdb_hle.elf" "$H/obj/cdb_hle.bin" "$OUT" "$WORDS" "${BANK0:-0}" "$LLVM/llvm-size" <<'PY'
import struct, subprocess, sys
elf, binf, out, words = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
bank0 = int(sys.argv[5])          # BANK0: two image files, OUT = words 0 .. BANK0 - 1, OUT_1 = the rest
sz = subprocess.run([sys.argv[6], '-A', elf], capture_output=True, text=True).stdout
sec = {l.split()[0]: int(l.split()[1]) for l in sz.splitlines() if l.startswith('.')}
if sec.get('.data', 0):
    sys.exit(f'firmware has initialised .data ({sec[".data"]} bytes): not supported (see link.ld)')
b = open(binf, 'rb').read()
used = sum(sec.get(k, 0) for k in ('.text', '.rodata', '.bss', '.smpc_text', '.smpc_rodata', '.smpc_bss', '.noinit'))
if len(b) > words * 4 or used > words * 4 - 1024:
    sys.exit(f'firmware does not fit: image {len(b)}, code+data {used}, RAM {words * 4} bytes')
b += bytes(words * 4 - len(b))
if 0 < bank0 < words:
    with open(out, 'w') as f:
        for i in range(bank0):
            f.write('%08x\n' % struct.unpack_from('<I', b, 4 * i)[0])
    with open(out[:-4] + '_1.hex', 'w') as f:
        for i in range(bank0, words):
            f.write('%08x\n' % struct.unpack_from('<I', b, 4 * i)[0])
else:
    with open(out, 'w') as f:
        for i in range(words):
            f.write('%08x\n' % struct.unpack_from('<I', b, 4 * i)[0])
print('firmware: ' + ' '.join(f'{k} {v}' for k, v in sec.items() if v and k != '.data') +
      f' bytes, {words * 4 - used} bytes left for the stack -> {out}' + (f' + {out[:-4]}_1.hex' if 0 < bank0 < words else ''))
PY
