# build_bwidow_dl.py -- build sim/bwidow_dl.hex (the download image the GHDL tb streams)
# from the real bwidow.zip.  Run from this sim/ directory:  python build_bwidow_dl.py
#
# The download order is the MRA's <rom index="0"> part order (= exactly what the working
# MiSTer core receives).  dn_addr is just the running byte offset; pgmrom.vhd / vecrom.vhd
# self-place by dn_addr range (pgmrom 0x0000-0x5FFF, vecrom 0x6000-0x9FFF, PROM 0xA000).
#   101.d1|102.ef1|103.h1|104.j1|105.kl1|106.m1  (6x4K program ROM)
#   107.l7|107.l7                                 (2K vector ROM, MIRRORED to fill 4K)
#   108.mn7|109.np7|110.r7                         (3x4K vector ROM)
#   136002-125.n4                                  (256B AVG state PROM)
import zipfile, sys, os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")   # fpga/blackwidow/
order = ["136017-101.d1", "136017-102.ef1", "136017-103.h1", "136017-104.j1",
         "136017-105.kl1", "136017-106.m1",
         "136017-107.l7", "136017-107.l7",
         "136017-108.mn7", "136017-109.np7", "136017-110.r7",
         "136002-125.n4"]

z = zipfile.ZipFile(os.path.join(ROOT, "bwidow.zip"))
blobs = {n: z.read(n) for n in z.namelist()}
data = bytearray()
for n in order:
    if n not in blobs:
        print("MISSING", n, "-- have:", sorted(blobs)); sys.exit(1)
    print(f"  {n}: {len(blobs[n])} bytes -> dn 0x{len(data):05X}")
    data += blobs[n]

with open("bwidow_dl.hex", "w") as f:
    for b in data:
        f.write(f"{b:02X}\n")
print(f"wrote bwidow_dl.hex: {len(data)} bytes (0x{len(data):05X}), last dn_addr 0x{len(data)-1:04X}")
# 6502 reset vector lives in the program ROM @ CPU $FFFC/$FFFD (top of pgmrom).
