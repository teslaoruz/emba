"""Typing reaches the ask box: load the real QML on the Qt host, open the ask box
the way a click does, send key events into the window, read the text field back.
Runs offscreen, so it never touches your desktop.

    QT_QPA_PLATFORM=offscreen python tests/ui_keys.py
"""
import os
import sys
import tempfile
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(APP / "desktop"))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["EMBA_SOCKET"] = str(Path(tempfile.gettempdir()) / f"emba-uikeys-{os.getpid()}.sock")

import host  # noqa: E402
from PySide6.QtCore import QEvent, QObject, QTimer, Qt  # noqa: E402
from PySide6.QtGui import QGuiApplication, QKeyEvent  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterSingletonInstance, qmlRegisterType  # noqa: E402

app = QGuiApplication(sys.argv)
api = host.QuickshellApi(app)
qmlRegisterSingletonInstance(host.QuickshellApi, "Quickshell", 1, 0, "Quickshell", api)
qmlRegisterType(host.Singleton, "Quickshell", 1, 0, "Singleton")
for cls in (host.Process, host.StdioCollector, host.SplitParser, host.FileView, host.SocketServer, host.Socket,
            host.IpcHandler):
    qmlRegisterType(cls, "Quickshell.Io", 1, 0, cls.__name__)
engine = QQmlApplicationEngine()
engine.addImportPath(str(host.stage_shared_qml()))
engine.load(str(APP / "desktop" / "main.qml"))
import shiboken6  # noqa: E402
from PySide6.QtQuick import QQuickWindow  # noqa: E402

win = shiboken6.wrapInstance(shiboken6.getCppPointer(engine.rootObjects()[0])[0], QQuickWindow)
island = win.findChild(QObject, "island")
fails = []


def check(ok, what):
    print(("ok    " if ok else "FAIL  ") + what)
    if not ok:
        fails.append(what)


def run():
    win.requestActivate()
    island.setProperty("forcedView", "ask")
    island.setProperty("open", True)
    QTimer.singleShot(900, type_into)


def type_into():
    field = win.findChild(QObject, "askInput")
    check(field is not None, "ask box is shown")
    if field is None:
        return app.quit()
    check(bool(field.property("activeFocus")), "ask box has the keyboard")
    for ch in "hello there":
        code = Qt.Key_Space if ch == " " else Qt.Key(ord(ch.upper()))
        for kind in (QEvent.KeyPress, QEvent.KeyRelease):
            QGuiApplication.sendEvent(win, QKeyEvent(kind, code, Qt.NoModifier, ch))
    QTimer.singleShot(300, lambda: after(field))


def after(field):
    check(field.property("text") == "hello there", f"typed text arrives ({field.property('text')!r})")
    for kind in (QEvent.KeyPress, QEvent.KeyRelease):
        QGuiApplication.sendEvent(win, QKeyEvent(kind, Qt.Key_Escape, Qt.NoModifier))
    QTimer.singleShot(400, lambda: (check(not island.property("open"), "Escape closes it"), app.quit()))


QTimer.singleShot(1500, run)
app.exec()
sys.exit(1 if fails else 0)
