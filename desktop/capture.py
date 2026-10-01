#!/usr/bin/env python3
"""Drag a rectangle, get a PNG. For Windows and X11, where there is no
slurp/grim or `screencapture -i`. Prints the file path, or nothing if cancelled.

    python desktop/capture.py OUT.png
"""
import sys

from PySide6.QtCore import QPoint, QRect, Qt
from PySide6.QtGui import QColor, QGuiApplication, QPainter, QPen
from PySide6.QtWidgets import QApplication, QWidget


class Picker(QWidget):
    def __init__(self, out):
        super().__init__(None, Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool)
        self.out = out
        self.area = QRect()
        for s in QGuiApplication.screens():
            self.area = self.area.united(s.geometry())
        self.setGeometry(self.area)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setCursor(Qt.CrossCursor)
        self.start = self.end = None

    def paintEvent(self, _):
        p = QPainter(self)
        p.fillRect(self.rect(), QColor(0, 0, 0, 90))
        if self.start and self.end:
            r = QRect(self.start, self.end).normalized()
            p.setCompositionMode(QPainter.CompositionMode_Clear)
            p.fillRect(r, Qt.transparent)
            p.setCompositionMode(QPainter.CompositionMode_SourceOver)
            p.setPen(QPen(QColor("#e2683c"), 2))
            p.drawRect(r)

    def mousePressEvent(self, e):
        self.start = self.end = e.position().toPoint()

    def mouseMoveEvent(self, e):
        self.end = e.position().toPoint()
        self.update()

    def mouseReleaseEvent(self, e):
        r = QRect(self.start, e.position().toPoint()).normalized().translated(self.area.topLeft())
        self.hide()
        QApplication.processEvents()
        if r.width() > 4 and r.height() > 4:
            screen = QGuiApplication.screenAt(r.center()) or QGuiApplication.primaryScreen()
            g = screen.geometry()
            shot = screen.grabWindow(0, r.x() - g.x(), r.y() - g.y(), r.width(), r.height())
            if shot.save(self.out, "PNG"):
                print(self.out, flush=True)
        QApplication.quit()

    def keyPressEvent(self, e):
        if e.key() == Qt.Key_Escape:
            QApplication.quit()


app = QApplication(sys.argv)
w = Picker(sys.argv[1])
w.show()
w.activateWindow()
app.exec()
