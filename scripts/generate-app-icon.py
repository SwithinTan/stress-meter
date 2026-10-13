#!/usr/bin/env python3
"""Regenerate the original geometric icon (development only; requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

scale = 3
image = Image.new("RGB", (1024 * scale, 1024 * scale), "#0c1723")
draw = ImageDraw.Draw(image)
def bounds(values):
    return tuple(int(value * scale) for value in values)

draw.arc(bounds((212, 212, 812, 812)), 135, 405, fill="#253c46", width=62 * scale)
draw.arc(bounds((212, 212, 812, 812)), 135, 319, fill="#71d4b5", width=62 * scale)
draw.ellipse(bounds((291, 671, 353, 733)), fill="#71d4b5")
draw.ellipse(bounds((682, 303, 748, 369)), fill="#e7b66f")
# The level line has no medical heartbeat or percentage symbolism.
draw.rounded_rectangle(bounds((392, 487, 632, 539)), radius=26 * scale, fill="#eef5f2")
output = Path(__file__).resolve().parents[1] / "WatchApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
image.resize((1024, 1024), Image.Resampling.LANCZOS).save(output)
print(output)
