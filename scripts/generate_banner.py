#!/usr/bin/env python3
"""Makes docs/images/banner.png, the 1280x640 picture used for the GitHub
link preview (repo Settings > Social preview) and the top of the README."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "Niyat/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
RUQAA = ROOT / "Niyat/Resources/Fonts/ArefRuqaa-Bold.ttf"
SANS_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
OUT = ROOT / "docs/images/banner.png"

W, H = 1280, 640
GOLD = (222, 186, 98)

image = Image.new("RGB", (W, H), (10, 10, 12))
glow = Image.new("RGB", (W, H), (0, 0, 0))
ImageDraw.Draw(glow).ellipse((60, 60, 600, 600), fill=(60, 50, 25))
image = Image.blend(image, glow.filter(ImageFilter.GaussianBlur(120)), 0.6)

icon = Image.open(ICON).convert("RGBA").resize((400, 400), Image.LANCZOS)
mask = Image.new("L", icon.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 400, 400), radius=90, fill=255)
image.paste(icon, (130, 120), mask)

draw = ImageDraw.Draw(image)
x = 620
draw.text((x, 150), "Niyat", font=ImageFont.truetype(SANS_BOLD, 110), fill=(245, 245, 245))
draw.text((x + 360, 150), "نيّة", font=ImageFont.truetype(str(RUQAA), 96), fill=GOLD,
          direction="rtl", language="ar")
draw.text((x, 300), "Prayer times, Qur'an and Qibla", font=ImageFont.truetype(SANS, 40), fill=(220, 220, 220))
draw.text((x, 355), "for iPhone", font=ImageFont.truetype(SANS, 40), fill=(220, 220, 220))
draw.text((x, 440), "Free forever · No ads · No tracking", font=ImageFont.truetype(SANS, 30), fill=GOLD)

OUT.parent.mkdir(parents=True, exist_ok=True)
image.save(OUT, optimize=True)
print(f"Wrote {OUT}")
