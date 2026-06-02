# build_gravitar_dl.py -- build sim/gravitar_dl.hex from the real gravitar.zip.
# Run from this sim/ directory:  python build_gravitar_dl.py
#
# Same download layout as Black Widow (pgmrom 6x4K, vecrom 210 mirrored + 207/208/309, PROM),
# in the Gravitar MRA <rom index="0"> order.  NOTE: the gravitar.zip uses short member names
# (136010.301) while the MRA lists MAME names (136010-301.d1) -- we use the ZIP names here, in
# the MRA's order.  Game-select mod byte = 1 (gravitar) vs 0 (bwidow).
import zipfile, sys, os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")   # fpga/blackwidow/
# MRA order (301..306 program | 210,210 vector-mirrored | 207,208,309 vector | 125 PROM):
order = ["136010.301", "136010.302", "136010.303", "136010.304", "136010.305", "136010.306",
         "136010.210", "136010.210",
         "136010.207", "136010.208", "136010.309",
         "136002-125.n4"]

z = zipfile.ZipFile(os.path.join(ROOT, "gravitar.zip"))
blobs = {n: z.read(n) for n in z.namelist()}
data = bytearray()
for n in order:
    if n not in blobs:
        print("MISSING", n, "-- have:", sorted(blobs)); sys.exit(1)
    print(f"  {n}: {len(blobs[n])} bytes -> dn 0x{len(data):05X}")
    data += blobs[n]

with open("gravitar_dl.hex", "w") as f:
    for b in data:
        f.write(f"{b:02X}\n")
print(f"wrote gravitar_dl.hex: {len(data)} bytes (0x{len(data):05X}), last dn_addr 0x{len(data)-1:04X}")
