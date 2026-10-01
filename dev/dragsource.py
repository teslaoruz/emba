"""A tiny window that offers one file for dragging, to test drops on Emba for real.
usage: .venv/bin/python dev/dragsource.py FILE"""
import sys

from PySide6.QtCore import QMimeData, Qt, QUrl
from PySide6.QtGui import QDrag
from PySide6.QtWidgets import QApplication, QLabel


class Source(QLabel):
    def __init__(self, path):
        super().__init__(f"drag me\n{path.split('/')[-1]}")
        self.path = path
        self.setAlignment(Qt.AlignCenter)
        self.setWindowTitle("emba-drag-source")
        self.resize(220, 120)
        self.setStyleSheet("background:#2a2f41;color:white;font-size:15px")

    def mousePressEvent(self, e):
        drag = QDrag(self)
        mime = QMimeData()
        mime.setUrls([QUrl.fromLocalFile(self.path)])
        drag.setMimeData(mime)
        drag.exec(Qt.CopyAction)


app = QApplication(sys.argv)
w = Source(sys.argv[1])
w.show()
app.exec()
