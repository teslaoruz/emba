"""Render assets/emba.svg to the PNG and ICO icons the packages need.
usage: .venv/bin/python dev/icons.py"""
import sys
from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtGui import QGuiApplication, QImage, QPainter
from PySide6.QtSvg import QSvgRenderer

root = Path(__file__).resolve().parent.parent
app = QGuiApplication(sys.argv)
svg = QSvgRenderer(str(root / "assets" / "emba.svg"))
out = root / "assets"
for size in (16, 32, 48, 64, 128, 256, 512):
    img = QImage(size, size, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    svg.render(p)
    p.end()
    img.save(str(out / f"emba-{size}.png"))
QImage(str(out / "emba-256.png")).save(str(out / "emba.ico"))
print("icons written to", out)
