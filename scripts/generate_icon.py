#!/usr/bin/env python3
"""Draws the app icon (crescent and star on a green gradient). Needs Pillow."""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # draw big, then downsample for smooth edges
S = SIZE * SCALE
OUT = Path(__file__).resolve().parent.parent / "Niyati/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

top, bottom = (16, 110, 90), (4, 40, 34)
gold = (217, 176, 88)

img = Image.new("RGB", (S, S))
px = img.load()
for y in range(S):
    for x in range(S):
        t = min(1.0, (x + y) / (2 * S) * 1.15)
        px[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))

# Soft glow behind the moon.
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse([S * 0.2, S * 0.2, S * 0.8, S * 0.8], fill=70)
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.08))
img = Image.composite(Image.new("RGB", (S, S), (60, 160, 130)), img, glow)

# Crescent: a gold disc minus an offset disc.
moon = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(moon)
cx, cy, r = S * 0.47, S * 0.5, S * 0.30
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
ox, oy, orad = cx + r * 0.42, cy - r * 0.18, r * 0.86
d.ellipse([ox - orad, oy - orad, ox + orad, oy + orad], fill=0)
img.paste(Image.new("RGB", (S, S), gold), (0, 0), moon)

# Five-pointed star inside the crescent's opening.
sx, sy, outer = S * 0.66, S * 0.42, S * 0.085
inner = outer * 0.42
points = []
for i in range(10):
    ang = -math.pi / 2 + i * math.pi / 5
    rad = outer if i % 2 == 0 else inner
    points.append((sx + rad * math.cos(ang), sy + rad * math.sin(ang)))
ImageDraw.Draw(img).polygon(points, fill=gold)

img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT, optimize=True)
print(f"Wrote {OUT}")
