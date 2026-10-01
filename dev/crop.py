"""Crop and upscale a region of a screenshot so small details are visible.
usage: python3 dev/crop.py in.png out.png x y w h [scale]"""
import sys
from PIL import Image

src, dst, x, y, w, h = sys.argv[1], sys.argv[2], *map(int, sys.argv[3:7])
k = int(sys.argv[7]) if len(sys.argv) > 7 else 4
Image.open(src).crop((x, y, x + w, y + h)).resize((w * k, h * k), Image.NEAREST).save(dst)
