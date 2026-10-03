"""Emba in the system tray: Open, Settings, Quit. Needs PySide6.

On its own (Emba on Quickshell starts it):   python desktop/tray.py
Inside the Qt host:                         tray.attach(app)
It leaves when Emba does.
"""
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

from PySide6.QtGui import QAction, QIcon
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

APP = Path(__file__).resolve().parent.parent


def emba(*args):
    subprocess.Popen([sys.executable if Path(sys.executable).exists() else "python3", str(APP / "bin" / "emba"), *args],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def attach(app):
    """Add the tray icon to a running QApplication; returns it (keep a reference)."""
    if not QSystemTrayIcon.isSystemTrayAvailable():
        return None
    tray = QSystemTrayIcon(QIcon(str(APP / "assets" / "emba.svg")), app)
    tray.setToolTip("Emba")
    menu = QMenu()
    for label, args in (("Open", ["open"]), ("Settings", ["settings"]), ("Ask…", ["ask"])):
        a = QAction(label, menu)
        a.triggered.connect(lambda _=False, args=args: emba(*args))
        menu.addAction(a)
    menu.addSeparator()
    quit_action = QAction("Quit Emba", menu)
    quit_action.triggered.connect(lambda: emba("quit"))
    menu.addAction(quit_action)
    tray.setContextMenu(menu)
    tray.activated.connect(lambda reason: emba("toggle") if reason == QSystemTrayIcon.Trigger else None)
    tray._menu = menu  # keep the menu alive with the icon
    tray.show()
    return tray


def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    tray = attach(app)
    if tray is None:
        return 0  # no tray on this desktop: nothing to do
    if os.name != "nt":  # leave with Emba
        parent = os.getppid()

        def watch():
            while True:
                time.sleep(2)
                if os.getppid() != parent:
                    os._exit(0)

        threading.Thread(target=watch, daemon=True).start()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
