#!/usr/bin/env python3
"""Draws the app icon: a gold crescent and star glowing on near-black.

Writes the three variants iOS uses: default, dark, and tinted (grayscale,
which iOS recolours to match the user's Home Screen tint). Needs Pillow.
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageOps

SIZE = 1024
SCALE = 3
S = SIZE * SCALE
OUT = Path(__file__).resolve().parent.parent / "Niyat/Resources/Assets.xcassets/AppIcon.appiconset"

INK = (4, 6, 9)
EMERALD = (3, 70, 55)
GOLD = (248, 202, 88)


def radial(center, radius, color, strength):
    mask = Image.new("L", (S, S), 0)
    cx, cy = center
    ImageDraw.Draw(mask).ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=strength)
    mask = mask.filter(ImageFilter.GaussianBlur(radius * 0.45))
    return Image.new("RGB", (S, S), color), mask


def crescent_mask():
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    cx, cy, r = S * 0.46, S * 0.52, S * 0.29
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    ox, oy, orad = cx + r * 0.45, cy - r * 0.2, r * 0.84
    d.ellipse([ox - orad, oy - orad, ox + orad, oy + orad], fill=0)
    sx, sy, outer = S * 0.67, S * 0.40, S * 0.078
    inner = outer * 0.42
    points = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rad = outer if i % 2 == 0 else inner
        points.append((sx + rad * math.cos(ang), sy + rad * math.sin(ang)))
    d.polygon(points, fill=255)
    return mask


def draw(background):
    img = Image.new("RGB", (S, S), background)
    if background != (0, 0, 0):
        for center, radius, color, strength in [
            ((S * 0.2, S * 0.15), S * 0.75, EMERALD, 255),
            ((S * 0.9, S * 0.95), S * 0.55, (8, 20, 48), 200),
        ]:
            layer, mask = radial(center, radius, color, strength)
            img = Image.composite(layer, img, mask)
    shape = crescent_mask()
    glow = shape.filter(ImageFilter.GaussianBlur(S * 0.03)).point(lambda v: int(v * 0.7))
    img = Image.composite(Image.new("RGB", (S, S), (190, 140, 40)), img, glow)
    img.paste(Image.new("RGB", (S, S), GOLD), (0, 0), shape)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


draw(INK).save(OUT / "AppIcon.png", optimize=True)
draw((0, 0, 0)).save(OUT / "AppIcon-Dark.png", optimize=True)
tinted = ImageOps.grayscale(draw((0, 0, 0))).point(lambda v: min(255, int(v * 1.25)))
tinted.convert("RGB").save(OUT / "AppIcon-Tinted.png", optimize=True)
print("Wrote icons to", OUT)
