"""Where the island is in each grabbed frame: its left edge along the top row
and its bottom edge down the right column (the island is pure black, #000).

    python dev/edges.py DIR        (frames from dev/openclose.sh)
"""
import sys
from pathlib import Path

from PySide6.QtGui import QGuiApplication, QImage

app = QGuiApplication(sys.argv[:1])


def black(img, x, y):
    c = img.pixelColor(x, y)
    return c.red() < 6 and c.green() < 6 and c.blue() < 6


for f in sorted(Path(sys.argv[1]).glob("*.png")):
    img = QImage(str(f))
    w, h = img.width(), img.height()
    row = 4  # just under the screen edge
    left = next((x for x in range(w) if all(black(img, x + d, row) for d in range(3))), w)
    col = w - 6
    bottom = next((y for y in range(h - 1, -1, -1) if black(img, col, y)), -1)
    print(f"{f.stem:12} left {w - left:4}  bottom {bottom + 1:4}")
