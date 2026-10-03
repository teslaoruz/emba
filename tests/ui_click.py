"""Clicking the overview's "Ask…" field opens the ask box, and the Sessions
tab returns to the sessions (offscreen, no desktop input).
    QT_QPA_PLATFORM=offscreen python tests/ui_click.py"""
import os
import sys
import tempfile
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(APP / "desktop"))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["EMBA_SOCKET"] = str(Path(tempfile.gettempdir()) / f"emba-uiclick-{os.getpid()}.sock")

import host  # noqa: E402
import shiboken6  # noqa: E402
from PySide6.QtCore import QEvent, QObject, QPointF, QTimer, Qt  # noqa: E402
from PySide6.QtGui import QGuiApplication, QMouseEvent  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterSingletonInstance, qmlRegisterType  # noqa: E402
from PySide6.QtQuick import QQuickItem, QQuickWindow  # noqa: E402

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
win = shiboken6.wrapInstance(shiboken6.getCppPointer(engine.rootObjects()[0])[0], QQuickWindow)
island = win.findChild(QObject, "island")


def click(x, y):
    for kind in (QEvent.MouseButtonPress, QEvent.MouseButtonRelease):
        p = QPointF(x, y)
        QGuiApplication.sendEvent(win, QMouseEvent(kind, p, p, Qt.LeftButton,
                                                   Qt.LeftButton if kind == QEvent.MouseButtonPress else Qt.NoButton,
                                                   Qt.NoModifier))


def step1():
    import json, subprocess
    subprocess.run([sys.executable, str(APP / "hook" / "emba-hook")], input=json.dumps({"hook_event_name": "PreToolUse", "session_id": "s1", "cwd": "/tmp/x", "tool_name": "Edit", "tool_input": {"file_path": "a.py"}}), text=True, env=os.environ)
    QTimer.singleShot(400, lambda: island.setProperty("open", True))   # the overview
    QTimer.singleShot(1200, step2)


def step2():
    field = win.findChild(QQuickItem, "askField")
    print("view before:", island.property("view"), "| field found:", field is not None)
    if field:
        c = field.mapToScene(QPointF(field.width() / 2, field.height() / 2))
        print("clicking at", round(c.x()), round(c.y()))
        click(c.x(), c.y())
    QTimer.singleShot(900, step3)


def step3():
    print("view after:", island.property("view"))
    results.append(island.property("view") == "ask")
    tabs = win.findChild(QQuickItem, "tabs")
    back = tabs.childItems()[0] if tabs else None  # Sessions
    if back:
        c = back.mapToScene(QPointF(back.width() / 2, back.height() / 2))
        click(c.x(), c.y())
    QTimer.singleShot(900, step4)


def step4():
    print("after back:", island.property("view"))
    results.append(island.property("view") == "overview")
    app.quit()


results = []


QTimer.singleShot(1500, step1)
app.exec()
sys.exit(0 if results == [True, True] else 1)
