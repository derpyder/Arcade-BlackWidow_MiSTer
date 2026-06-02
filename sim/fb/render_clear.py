#!/usr/bin/env python3
# Bright, full-size render of the BW attract (orient C = bwidow_sw default) so the
# content is actually visible -- every lit point drawn at FULL brightness as a 3x3
# blob (the real attract is dim/sparse: ~776 pts, mostly dim blue).  Geometry is
# IDENTICAL to bwidow_sw (FILL *11/16, fxs=480+scx, fys=360-scy); only brightness
# + blob size differ, for human visibility.
from PIL import Image, ImageDraw
FRAME = "../bwidow_frame.txt"
W, H = 960, 720

img = Image.new("RGB", (W, H), (0, 0, 0))
px = img.load()
n = 0
for l in open(FRAME):
    f = l.split()
    if len(f) < 4: continue
    ax, ay, rgb, az = map(int, f[:4])
    if rgb == 0 or (az >> 3) == 0: continue          # only lit draws
    cx = ax ^ 512; sx = (cx * 11) >> 4; scx = sx - 352
    cy = ay ^ 512; sy = (cy * 11) >> 4; scy = sy - 352
    x = 480 + scx; y = 360 - scy                      # orient C (flip Y)
    # FULL brightness colour from the 3 rgb bits (R=bit2,G=bit1,B=bit0)
    col = (255 if rgb & 4 else 0, 255 if rgb & 2 else 0, 255 if rgb & 1 else 0)
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            xx, yy = x + dx, y + dy
            if 0 <= xx < W and 0 <= yy < H:
                px[xx, yy] = col
    n += 1
# frame + label so the screen extent is obvious
d = ImageDraw.Draw(img)
d.rectangle([0, 0, W - 1, H - 1], outline=(40, 40, 40))
d.text((10, 8), f"Black Widow attract -- {n} lit pts, FILL 11/16, orient C (960x720)", fill=(180, 180, 180))
img.save("bw_attract_clear.png")
print(f"wrote bw_attract_clear.png  ({n} lit pts at full brightness)")
