#!/usr/bin/env python3
"""Draws the Niyat app icon in the Onyx colourway.

A thin gold ring (the prayer dial) with five points for the five prayers, the
next one glowing, around an eight-pointed star (Rub el Hizb). Writes the
default, dark and tinted variants iOS uses. Needs Pillow.
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageOps

SIZE = 1024
SCALE = 3
S = SIZE * SCALE
C = S / 2
OUT = Path(__file__).resolve().parent.parent / "Niyat/Resources/Assets.xcassets/AppIcon.appiconset"

GOLD = (222, 184, 98)
GOLD_LIGHT = (246, 222, 160)


def star_points(cx, cy, r, inner_ratio=0.765, rotation=0.0):
    pts = []
    for i in range(16):
        a = i * math.pi / 8 - math.pi / 2 + rotation
        rr = r if i % 2 == 0 else r * inner_ratio
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def ring_point(fraction, r):
    # Same mapping as the app's prayer dial: midnight at the bottom, noon at the top.
    a = fraction * 2 * math.pi + math.pi / 2
    return C + r * math.cos(a), C + r * math.sin(a)


def draw_art(mask_only=False):
    """Returns an L-mode mask of all the gold line art, plus a separate glow mask."""
    art = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(art)
    ring_r = S * 0.335
    w = int(S * 0.012)

    # The dial ring.
    d.ellipse([C - ring_r, C - ring_r, C + ring_r, C + ring_r], outline=255, width=w)

    # Eight-pointed star, outline, with a smaller solid star inside.
    pts = star_points(C, C, S * 0.19)
    d.line(pts + pts[:2], fill=255, width=w, joint="curve")
    d.polygon(star_points(C, C, S * 0.085, rotation=math.pi / 8), fill=255)

    # Five prayers on the ring (roughly Fajr, Dhuhr, Asr, Maghrib, Isha).
    prayers = [0.22, 0.53, 0.66, 0.78, 0.86]
    glow = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(glow)
    for i, f in enumerate(prayers):
        x, y = ring_point(f, ring_r)
        r = S * (0.03 if i == 1 else 0.02)
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        if i == 1:
            gr = S * 0.09
            gd.ellipse([x - gr, y - gr, x + gr, y + gr], fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.04))
    return art, glow


def compose(background_top, background_bottom, transparent=False):
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        t = y / S
        row = tuple(int(background_top[i] + (background_bottom[i] - background_top[i]) * t) for i in range(3))
        for x in range(S):
            px[x, y] = row
    # A very soft warm light behind the centre.
    halo = Image.new("L", (S, S), 0)
    ImageDraw.Draw(halo).ellipse([C - S * 0.3, C - S * 0.3, C + S * 0.3, C + S * 0.3], fill=40)
    halo = halo.filter(ImageFilter.GaussianBlur(S * 0.12))
    img = Image.composite(Image.new("RGB", (S, S), (70, 55, 25)), img, halo)

    art, glow = draw_art()
    img = Image.composite(Image.new("RGB", (S, S), GOLD_LIGHT), img, glow.point(lambda v: int(v * 0.45)))
    soft = art.filter(ImageFilter.GaussianBlur(S * 0.006)).point(lambda v: int(v * 0.6))
    img = Image.composite(Image.new("RGB", (S, S), (150, 115, 50)), img, soft)
    img = Image.composite(Image.new("RGB", (S, S), GOLD), img, art)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


compose((22, 22, 24), (4, 4, 5)).save(OUT / "AppIcon.png", optimize=True)
compose((0, 0, 0), (0, 0, 0)).save(OUT / "AppIcon-Dark.png", optimize=True)
tinted = ImageOps.grayscale(compose((0, 0, 0), (0, 0, 0))).point(lambda v: min(255, int(v * 1.3)))
tinted.convert("RGB").save(OUT / "AppIcon-Tinted.png", optimize=True)
print("Wrote icons to", OUT)
