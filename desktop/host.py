#!/usr/bin/env python3
"""Emba's desktop host, for Windows, macOS and Linux desktops without layer-shell.

Emba's UI is written once, in QML, for Quickshell. This host runs those same
files on plain Qt by providing the handful of Quickshell types they use
(Singleton, Quickshell.env/execDetached/shellDir/screens, and Process,
StdioCollector, SplitParser, FileView, SocketServer, Socket, IpcHandler from
Quickshell.Io). Nothing here knows about sessions or agents; that all lives
in the shared App.qml.

    python3 desktop/host.py
"""

import getpass
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PySide6.QtCore import (ClassInfo, Property, QFileSystemWatcher, QObject, QPoint, QProcess, QProcessEnvironment, QRect,
                            QTimer, Signal,
                            Slot)
from PySide6.QtGui import QCursor, QGuiApplication, QIcon, QRegion
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import (ListProperty, QQmlApplicationEngine, QQmlComponent, QQmlEngine, qmlRegisterSingletonInstance,
                           qmlRegisterType)

APP = Path(__file__).resolve().parent.parent
SHARED = ["App.qml", "Theme.qml", "Pet.qml", "Island.qml", "Notch.qml", "Panda.qml", "Settings.qml", "Sounds.qml"]


def socket_address():
    """Same rule as hook/emba-hook's address()."""
    if os.environ.get("EMBA_SOCKET"):
        return os.environ["EMBA_SOCKET"]
    if os.name == "nt":
        return rf"\\.\pipe\emba-{getpass.getuser()}"
    run = os.environ.get("XDG_RUNTIME_DIR")
    return str(Path(run) / "emba.sock") if run else str(Path(tempfile.gettempdir()) / f"emba-{os.getuid()}.sock")


# ================================================================ Quickshell

@ClassInfo(DefaultProperty="data")
class Singleton(QObject):
    """Root of App.qml / Theme.qml: a plain object that may hold children."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._data = []

    def _append(self, obj):
        self._data.append(obj)

    def _at(self, i):
        return self._data[i]

    def _count(self):
        return len(self._data)

    data = ListProperty(QObject, append=_append, at=_at, count=_count)


class QuickshellApi(QObject):
    """The `Quickshell` singleton, as far as Emba uses it."""

    def __init__(self, app):
        super().__init__()
        self.app = app

    @Slot(str, result=str)
    def env(self, name):
        return os.environ.get(name, "")

    @Slot("QVariantList")
    def execDetached(self, cmd):
        try:
            subprocess.Popen([str(c) for c in cmd], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=os.name != "nt")
        except OSError:
            pass

    @Property(str, constant=True)
    def shellDir(self):
        return str(APP)

    @Property("QVariantList", constant=True)
    def screens(self):
        return list(self.app.screens())

    # not part of Quickshell: Island.qml uses it when present for the eyes
    @Slot(result=QPoint)
    def cursorPos(self):
        return QCursor.pos()

    # not part of Quickshell: lets the window pass clicks through outside the island
    @Slot(QObject, int, int, int, int)
    def setMask(self, window, x, y, w, h):
        window.setMask(QRegion(QRect(x, y, max(w, 1), max(h, 1))))

    @Slot(str, result="QVariantMap")
    def availableGeometry(self, name):
        screen = next((s for s in self.app.screens() if s.name() == name), self.app.primaryScreen())
        g = screen.availableGeometry()
        return {"x": g.x(), "y": g.y(), "width": g.width(), "height": g.height()}


# ================================================================ Quickshell.Io

class SplitParser(QObject):
    read = Signal(str, arguments=["data"])

    def __init__(self, parent=None):
        super().__init__(parent)
        self._marker = "\n"
        self._buf = ""

    def _get_marker(self):
        return self._marker

    def _set_marker(self, m):
        self._marker = m or "\n"

    splitMarker = Property(str, _get_marker, _set_marker)

    def feed(self, text):
        self._buf += text
        while self._marker in self._buf:
            line, self._buf = self._buf.split(self._marker, 1)
            self.read.emit(line)

    def finish(self):
        if self._buf:
            line, self._buf = self._buf, ""
            self.read.emit(line)


class StdioCollector(QObject):
    textChanged = Signal()
    streamFinished = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._text = ""

    def _get_text(self):
        return self._text

    text = Property(str, _get_text, notify=textChanged)

    @Property(bool)
    def waitForEnd(self):
        return True

    @waitForEnd.setter
    def waitForEnd(self, _):
        pass

    def feed(self, text):
        self._text += text

    def reset(self):
        self._text = ""
        self.textChanged.emit()

    def finish(self):
        self.textChanged.emit()
        self.streamFinished.emit()


class Process(QObject):
    runningChanged = Signal()
    commandChanged = Signal()
    started = Signal()
    exited = Signal(int, int, arguments=["exitCode", "exitStatus"])

    def __init__(self, parent=None):
        super().__init__(parent)
        self._command = []
        self._cwd = ""
        self._env = {}
        self._stdout = None
        self._stderr = None
        self._proc = None

    def _get_command(self):
        return self._command

    def _set_command(self, c):
        self._command = [str(x) for x in (c or [])]
        self.commandChanged.emit()

    command = Property("QVariantList", _get_command, _set_command, notify=commandChanged)

    def _get_cwd(self):
        return self._cwd

    def _set_cwd(self, d):
        self._cwd = d or ""

    workingDirectory = Property(str, _get_cwd, _set_cwd)

    # extra variables on top of the normal environment
    environment = Property("QVariantMap", lambda self: self._env, lambda self, e: setattr(self, "_env", dict(e or {})))

    def _get_stdout(self):
        return self._stdout

    def _set_stdout(self, p):
        self._stdout = p

    stdout = Property(QObject, _get_stdout, _set_stdout)

    def _get_stderr(self):
        return self._stderr

    def _set_stderr(self, p):
        self._stderr = p

    stderr = Property(QObject, _get_stderr, _set_stderr)

    def _get_running(self):
        return self._proc is not None

    def _set_running(self, on):
        if on and self._proc is None and self._command:
            self._start()
        elif not on and self._proc is not None:
            self._proc.kill()

    running = Property(bool, _get_running, _set_running, notify=runningChanged)

    def _start(self):
        program = shutil.which(self._command[0]) or self._command[0]
        p = QProcess(self)
        if self._env:
            env = QProcessEnvironment.systemEnvironment()
            for k, v in self._env.items():
                env.insert(str(k), str(v))
            p.setProcessEnvironment(env)
        if self._cwd and Path(self._cwd).is_dir():
            p.setWorkingDirectory(self._cwd)
        for parser in (self._stdout, self._stderr):
            if isinstance(parser, StdioCollector):
                parser.reset()
        p.readyReadStandardOutput.connect(lambda: self._feed(self._stdout, p.readAllStandardOutput()))
        p.readyReadStandardError.connect(lambda: self._feed(self._stderr, p.readAllStandardError()))
        p.finished.connect(lambda code, status: self._done(p, code, int(status.value)))
        p.errorOccurred.connect(lambda err: self._done(p, 127, 1) if err == QProcess.ProcessError.FailedToStart else None)
        self._proc = p
        self.runningChanged.emit()
        p.start(program, self._command[1:])
        self.started.emit()

    @staticmethod
    def _feed(parser, data):
        if parser is not None:
            parser.feed(bytes(data).decode(errors="replace"))

    def _done(self, p, code, status):
        if self._proc is not p:
            return
        try:
            self._feed(self._stdout, p.readAllStandardOutput())
            self._feed(self._stderr, p.readAllStandardError())
        except RuntimeError:  # the app is shutting down and Qt already freed the process
            return
        for parser in (self._stdout, self._stderr):
            if parser is not None:
                parser.finish()
        self._proc = None
        p.deleteLater()
        self.runningChanged.emit()
        self.exited.emit(code, status)


class FileView(QObject):
    pathChanged = Signal()
    loaded = Signal()
    loadFailed = Signal(int, arguments=["error"])
    fileChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._path = ""
        self._text = ""
        self._watch = False
        self._watcher = None
        self._pending = False

    def _get_path(self):
        return self._path

    def _set_path(self, p):
        if p == self._path:
            return
        self._path = p
        self.pathChanged.emit()
        self._rewatch()
        self.reload()

    path = Property(str, _get_path, _set_path, notify=pathChanged)

    def _get_watch(self):
        return self._watch

    def _set_watch(self, on):
        self._watch = bool(on)
        self._rewatch()

    watchChanges = Property(bool, _get_watch, _set_watch)

    # accepted for compatibility; this host always writes atomically and quietly
    printErrors = Property(bool, lambda self: False, lambda self, v: None)
    atomicWrites = Property(bool, lambda self: True, lambda self, v: None)

    def _rewatch(self):
        if not self._watch or not self._path:
            return
        if self._watcher is None:
            self._watcher = QFileSystemWatcher(self)
            self._watcher.fileChanged.connect(self._changed)
            self._watcher.directoryChanged.connect(self._changed)
        self._watcher.removePaths(self._watcher.files() + self._watcher.directories())
        target = Path(self._path)
        self._watcher.addPath(str(target if target.exists() else target.parent))

    def _changed(self, _):
        self._rewatch()  # files replaced by rename drop off the watch list
        self.fileChanged.emit()

    @Slot()
    def reload(self):
        if self._pending or not self._path:
            return
        self._pending = True
        QTimer.singleShot(0, self._load)

    def _load(self):
        self._pending = False
        try:
            self._text = Path(self._path).read_text(encoding="utf-8")
        except OSError:
            self.loadFailed.emit(1)
            return
        self.loaded.emit()

    @Slot(result=str)
    def text(self):
        return self._text

    @Slot(str)
    def setText(self, text):
        target = Path(self._path)
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_suffix(target.suffix + ".tmp")
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, target)
        self._text = text
        self._rewatch()
        self.fileChanged.emit()


class Socket(QObject):
    """A server-side connection (made by SocketServer) or a client (set path, then connected = true)."""
    connectedChanged = Signal()
    error = Signal(int, arguments=["error"])

    def __init__(self, parent=None):
        super().__init__(parent)
        self._sock = None
        self._parser = None
        self._path = ""
        self._served = False

    def _attach(self, sock, served=True):
        self._sock = sock
        self._served = served
        sock.readyRead.connect(lambda: self._parser and self._parser.feed(bytes(sock.readAll()).decode(errors="replace")))
        sock.disconnected.connect(self._gone)
        self.connectedChanged.emit()

    def _gone(self):
        if self._sock is not None:
            self._sock = None
            self.connectedChanged.emit()
            if self._served:  # QML did not create it, so nobody else will clean it up
                self.deleteLater()

    def _get_path(self):
        return self._path

    def _set_path(self, p):
        self._path = p

    path = Property(str, _get_path, _set_path)

    def _get_connected(self):
        return self._sock is not None

    def _set_connected(self, on):
        if not on and self._sock is not None:
            self._sock.disconnectFromServer()
        elif on and self._sock is None and self._path:
            s = QLocalSocket(self)
            s.connected.connect(lambda: self._attach(s, served=False))
            s.errorOccurred.connect(lambda e: self.error.emit(int(e.value)) if self._sock is None else None)
            s.connectToServer(self._path.removeprefix("\\\\.\\pipe\\") if os.name == "nt" else self._path)

    connected = Property(bool, _get_connected, _set_connected, notify=connectedChanged)

    def _get_parser(self):
        return self._parser

    def _set_parser(self, p):
        self._parser = p

    parser = Property(QObject, _get_parser, _set_parser)

    @Slot(str)
    def write(self, text):
        if self._sock is not None:
            self._sock.write(text.encode())

    @Slot()
    def flush(self):
        if self._sock is not None:
            self._sock.flush()


class SocketServer(QObject):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._path = ""
        self._active = False
        self._handler = None
        self._server = None

    def _get_path(self):
        return self._path

    def _set_path(self, p):
        self._path = p
        self._listen()

    path = Property(str, _get_path, _set_path)

    def _get_active(self):
        return self._active

    def _set_active(self, on):
        self._active = bool(on)
        self._listen()

    active = Property(bool, _get_active, _set_active)

    def _get_handler(self):
        return self._handler

    def _set_handler(self, c):
        self._handler = c

    handler = Property(QQmlComponent, _get_handler, _set_handler)

    def _listen(self):
        if not (self._active and self._path) or self._server is not None:
            return
        name = self._path
        if os.name == "nt":
            name = name.removeprefix("\\\\.\\pipe\\")
        else:
            QLocalServer.removeServer(name)  # a stale file from a crash
        self._server = QLocalServer(self)
        self._server.setSocketOptions(QLocalServer.SocketOption.UserAccessOption)
        self._server.newConnection.connect(self._accept)
        if not self._server.listen(name):
            print(f"emba: cannot listen on {name}: {self._server.errorString()}", file=sys.stderr)

    def _accept(self):
        while self._server.hasPendingConnections():
            sock = self._server.nextPendingConnection()
            if self._handler is None:
                sock.disconnectFromServer()
                continue
            ctx = QQmlEngine.contextForObject(self)
            obj = self._handler.beginCreate(ctx)
            obj.setParent(self)
            obj._attach(sock)
            self._handler.completeCreate()


class IpcHandler(QObject):
    """Quickshell's IPC is Linux-only; here the `emba` CLI talks over the socket."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._target = ""

    target = Property(str, lambda self: self._target, lambda self, t: setattr(self, "_target", t))


# ================================================================ start

def stage_shared_qml():
    """The shared files import `qs` (Quickshell's name for its config dir); give them one."""
    root = Path(tempfile.gettempdir()) / f"emba-qml-{getpass.getuser()}"
    mod = root / "qs"
    mod.mkdir(parents=True, exist_ok=True)
    for name in SHARED:
        shutil.copy2(APP / name, mod / name)
    (mod / "qmldir").write_text("module qs\nsingleton App 1.0 App.qml\nsingleton Theme 1.0 Theme.qml\nsingleton Pet 1.0 Pet.qml\n"
                                "Island 1.0 Island.qml\nNotch 1.0 Notch.qml\nPanda 1.0 Panda.qml\nSettings 1.0 Settings.qml\n")
    return root


def already_running(address):
    s = QLocalSocket()
    s.connectToServer(address.removeprefix("\\\\.\\pipe\\") if os.name == "nt" else address)
    up = s.waitForConnected(300)
    s.abort()
    return up


def main():
    address = socket_address()
    os.environ["EMBA_SOCKET"] = address
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Emba")
    app.setQuitOnLastWindowClosed(False)
    icon = APP / "assets" / "emba.svg"
    if icon.exists():
        app.setWindowIcon(QIcon(str(icon)))
    if already_running(address):
        print("Emba is already running")
        return 0

    api = QuickshellApi(app)
    qmlRegisterSingletonInstance(QuickshellApi, "Quickshell", 1, 0, "Quickshell", api)
    qmlRegisterType(Singleton, "Quickshell", 1, 0, "Singleton")
    for cls in (Process, StdioCollector, SplitParser, FileView, SocketServer, Socket, IpcHandler):
        qmlRegisterType(cls, "Quickshell.Io", 1, 0, cls.__name__)

    engine = QQmlApplicationEngine()
    engine.addImportPath(str(stage_shared_qml()))
    engine.load(str(APP / "desktop" / "main.qml"))
    if not engine.rootObjects():
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
