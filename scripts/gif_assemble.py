#!/usr/bin/env python3
"""Assemble PNG frames into a looping GIF with one shared palette (less flicker, smaller file).

usage: gif_assemble.py out.gif width fps colors frame1.png frame2.png ...
Needs Pillow (pip3 install --user pillow).
"""
import sys
from PIL import Image

out, width, fps, colors, files = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5:]
frames = []
for f in files:
    im = Image.open(f).convert("RGB")
    h = round(im.height * width / im.width)
    frames.append(im.resize((width, h), Image.LANCZOS))

# Palette built from a strip of sampled frames so every part of the animation is represented.
sample = frames[:: max(1, len(frames) // 8)]
strip = Image.new("RGB", (width, sum(s.height for s in sample)))
y = 0
for s in sample:
    strip.paste(s, (0, y))
    y += s.height
pal = strip.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
q[0].save(out, save_all=True, append_images=q[1:], duration=int(1000 / fps), loop=0, optimize=True, disposal=1)
print(f"{out}: {len(q)} frames, {width}px, {len(open(out, 'rb').read()) // 1024} KB")
