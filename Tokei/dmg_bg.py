#!/usr/bin/env python3
"""Generate DMG background image for Tokei installer — light warm theme."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

W, H = 660, 400
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Warm light gradient background (top: warm white → bottom: soft peach)
for y in range(H):
    t = y / H
    r = int(245 - t * 12)
    g = int(242 - t * 16)
    b = int(238 - t * 20)
    draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

# Soft radial glow behind icon positions
def draw_glow(img, cx, cy, radius, color, alpha):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for r in range(radius, 0, -1):
        t = r / radius
        a = int(alpha * (1 - t * t))
        ld.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, a))
    layer = layer.filter(ImageFilter.GaussianBlur(radius // 3))
    return Image.alpha_composite(img, layer)

# Glow behind Tokei.app icon (left) and Applications (right)
icon_y = 190
img = draw_glow(img, 150, icon_y, 70, (255, 200, 170), 35)
img = draw_glow(img, 510, icon_y, 70, (200, 210, 240), 30)

# ── Fonts ──
def get_font(size):
    for path in [
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/Supplemental/Songti.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()

def get_mono(size):
    for path in [
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/Monaco.dfont",
        "/System/Library/Fonts/Supplemental/Courier New.ttf",
    ]:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()

# ── Smooth arrow ──
arrow_y = icon_y + 5
arrow_x1, arrow_x2 = 220, 440

# Coral brand color for arrow
coral = (235, 120, 90)
coral_light = (245, 165, 130)

# Soft shadow under arrow
shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.line([(arrow_x1, arrow_y + 3), (arrow_x2, arrow_y + 3)],
        fill=(180, 140, 120, 30), width=8)
shadow = shadow.filter(ImageFilter.GaussianBlur(6))
img = Image.alpha_composite(img, shadow)

# Arrow shaft — smooth gradient
arrow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ad = ImageDraw.Draw(arrow)

steps = 80
for i in range(steps):
    t = i / steps
    x = int(arrow_x1 + t * (arrow_x2 - arrow_x1 - 20))
    x_end = int(arrow_x1 + (i + 1) / steps * (arrow_x2 - arrow_x1 - 20))
    r = int(coral_light[0] + t * (coral[0] - coral_light[0]))
    g = int(coral_light[1] + t * (coral[1] - coral_light[1]))
    b = int(coral_light[2] + t * (coral[2] - coral_light[2]))
    ad.line([(x, arrow_y), (x_end, arrow_y)], fill=(r, g, b, 220), width=3)

# Arrow head
head_x = arrow_x2 - 8
ad.polygon([
    (head_x + 18, arrow_y),
    (head_x - 2, arrow_y - 13),
    (head_x - 2, arrow_y + 13),
], fill=(*coral, 230))
# Highlight on arrowhead
ad.polygon([
    (head_x + 14, arrow_y - 1),
    (head_x + 2, arrow_y - 8),
    (head_x + 2, arrow_y - 1),
], fill=(255, 180, 160, 70))

img = Image.alpha_composite(img, arrow)
draw = ImageDraw.Draw(img)

# ── Text ──
title_font = get_font(13)
hint_font = get_font(10)
mono_font = get_mono(9)
small_font = get_font(10)

# "Drag to Applications" above arrow
txt = "拖入 Applications 安装"
bbox = draw.textbbox((0, 0), txt, font=title_font)
tw = bbox[2] - bbox[0]
draw.text(((W - tw) // 2, arrow_y - 38), txt,
          fill=(120, 100, 90, 200), font=title_font)

# Bottom xattr hint
label = "首次打开被拦截?  "
cmd = "sudo xattr -rd com.apple.quarantine /Applications/Tokei.app"
lbox = draw.textbbox((0, 0), label, font=hint_font)
cbox = draw.textbbox((0, 0), cmd, font=mono_font)
lw = lbox[2] - lbox[0]
cw = cbox[2] - cbox[0]
total_w = lw + cw
start_x = (W - total_w) // 2
draw.text((start_x, H - 30), label, fill=(160, 140, 130, 150), font=hint_font)
draw.text((start_x + lw, H - 29), cmd, fill=(150, 130, 120, 140), font=mono_font)

# Top brand
ver = "Tokei · AI Coding Usage Monitor"
bbox = draw.textbbox((0, 0), ver, font=small_font)
vw = bbox[2] - bbox[0]
draw.text(((W - vw) // 2, 10), ver, fill=(170, 155, 145, 130), font=small_font)

# Convert to RGB
out = Image.new("RGB", (W, H), (245, 242, 238))
out.paste(img, mask=img)
out.save(os.path.join(os.path.dirname(__file__), "dmg_background.png"), quality=95)
print("Generated dmg_background.png")
