#!/usr/bin/env python3
"""Shrinks a screenshot to <width> px and palette-quantizes it (keeps the rounded-corner alpha).

usage: shots_post.py in.png out.png [width]
Needs Pillow (pip3 install --user pillow).
"""
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
width = int(sys.argv[3]) if len(sys.argv) > 3 else 880
im = Image.open(src).convert("RGBA")
if im.width > width:
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
q = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
q.save(dst, optimize=True)
print(f"{dst}: {q.width}x{q.height}, {len(open(dst, 'rb').read()) // 1024} KB")
