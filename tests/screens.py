"""Run Emba on this system's real display and save pictures of the island.

    python tests/screens.py OUTDIR

CI runs it on Windows, macOS and Linux and keeps the pictures, so the look can
be checked on systems nobody here sits in front of.
"""
import json
import subprocess
import sys
import threading
import time
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
PY = sys.executable
out = Path(sys.argv[1] if len(sys.argv) > 1 else "screens").resolve()
out.mkdir(parents=True, exist_ok=True)


def emba(*args):
    return subprocess.run([PY, str(APP / "bin" / "emba")] + list(args), capture_output=True, text=True, timeout=30).stdout


def hook(payload, *args):
    return subprocess.run([PY, str(APP / "hook" / "emba-hook")] + list(args), input=json.dumps(payload),
                          capture_output=True, text=True, timeout=60).stdout


def snap(name, wait=1.5):
    time.sleep(wait)
    emba("snapshot", str(out / f"{name}.png"))
    time.sleep(0.8)
    print(("saved " if (out / f"{name}.png").exists() else "MISSING ") + name)


emba("quit")
time.sleep(0.5)
print(emba("start"))
time.sleep(1.5)
snap("1-empty-hidden")
emba("toggle")
snap("2-welcome")
emba("toggle")

a = {"session_id": "a", "cwd": str(APP)}
hook({**a, "hook_event_name": "SessionStart"})
hook({**a, "hook_event_name": "UserPromptSubmit", "prompt": "fix the failing invoice test"})
hook({**a, "hook_event_name": "PreToolUse", "tool_name": "Edit", "tool_input": {"file_path": "Invoice.swift"}})
snap("3-compact")
emba("toggle")
snap("4-overview")
emba("toggle")

req = {**a, "hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_use_id": "t1",
       "tool_input": {"command": "rm -rf build && npm test"}}
t = threading.Thread(target=hook, args=(req,))
t.start()
snap("5-approval", 2.5)
emba("allow")
t.join()

hook({**a, "hook_event_name": "Stop", "last_assistant_message": "Fixed the rounding bug and added a test."})
snap("6-finished")
emba("care")
snap("7-care")
emba("settings")
time.sleep(1)
emba("quit")
print("done")
