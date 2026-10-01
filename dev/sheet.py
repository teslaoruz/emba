"""Stitch screenshots into one labelled grid: python3 dev/sheet.py out.png a.png b.png ..."""
import os
import sys
from PIL import Image, ImageDraw

out, paths = sys.argv[1], sys.argv[2:]
imgs = [Image.open(p).convert("RGB") for p in paths]
w, h = imgs[0].size
cols = 3
rows = (len(imgs) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * (h + 18)), "#111")
d = ImageDraw.Draw(sheet)
for i, (p, im) in enumerate(zip(paths, imgs)):
    x, y = (i % cols) * w, (i // cols) * (h + 18)
    sheet.paste(im, (x, y + 18))
    d.text((x + 6, y + 3), os.path.splitext(os.path.basename(p))[0].split("-", 1)[-1].lstrip("0123456789"), fill="#ccc")
sheet.save(out)
