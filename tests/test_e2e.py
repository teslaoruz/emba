"""End-to-end check on any OS: start Emba, feed it real hook payloads, answer
permission requests through the CLI, check what the hook prints.

    python tests/test_e2e.py          (EMBA_HOST=qt for the desktop host)

Exits non-zero on the first failure. CI runs it on Linux, macOS and Windows.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
PY = sys.executable
HOOK = [PY, str(APP / "hook" / "emba-hook")]
CLI = [PY, str(APP / "bin" / "emba")]


def emba(*args):
    return subprocess.run(CLI + list(args), capture_output=True, text=True, timeout=30).stdout.strip()


def hook(payload, *args):
    r = subprocess.run(HOOK + list(args), input=json.dumps(payload), capture_output=True, text=True, timeout=60)
    return r.stdout.strip()


def later(seconds, *args):
    t = threading.Timer(seconds, lambda: emba(*args))
    t.start()
    return t


def check(ok, what):
    if not ok:
        print(f"FAIL: {what}")
        emba("quit")
        sys.exit(1)
    print(f"ok    {what}")


def state():
    return json.loads(emba("state") or "{}")


emba("quit")
time.sleep(0.5)
print(emba("start"))

hook({"hook_event_name": "SessionStart", "session_id": "t1", "cwd": str(APP)})
check(any(s["sid"] == "t1" for s in state().get("sessions", [])), "session appears")

req = {"hook_event_name": "PermissionRequest", "session_id": "t1", "cwd": str(APP), "tool_name": "Bash",
       "tool_input": {"command": "ls"}, "tool_use_id": "toolu_1",
       "permission_suggestions": [{"type": "addRules", "rules": ["Bash(ls)"], "behavior": "allow", "destination": "session"}]}

later(1.5, "allow")
out = hook(req)
check('"behavior": "allow"' in out, f"allow reaches the hook ({out!r})")

later(1.5, "deny")
out = hook({**req, "tool_use_id": "toolu_2"})
check('"behavior": "deny"' in out, f"deny reaches the hook ({out!r})")

later(1.5, "set", "celebrate", "true")  # unrelated command must not answer
t = threading.Timer(2.5, lambda: hook({"hook_event_name": "PreToolUse", "session_id": "t1", "tool_name": "Read",
                                       "tool_input": {}}))
t.start()
out = hook({**req, "tool_use_id": "toolu_3"})
check(out == "", f"answer in terminal cancels quietly ({out!r})")

q = {"hook_event_name": "PermissionRequest", "session_id": "t1", "cwd": str(APP), "tool_name": "AskUserQuestion",
     "tool_use_id": "toolu_q", "tool_input": {"questions": [{"question": "Which one?", "header": "Pick", "multiSelect": False,
                                                              "options": [{"label": "A"}, {"label": "B"}]}]}}
later(1.5, "answer", "B")
out = hook(q)
check('"Which one?": "B"' in out and '"behavior": "allow"' in out, f"a question is answered with the option ({out!r})")

later(1.5, "allow")
out = hook({**q, "tool_use_id": "toolu_q2"})
check(out == "", f"a question allowed without answers goes back to the terminal ({out!r})")

hook({"hook_event_name": "SessionStart", "session_id": "cx", "cwd": str(APP)}, "--agent", "codex")
later(1.5, "allow")
out = hook({"hook_event_name": "PermissionRequest", "session_id": "cx", "cwd": str(APP), "tool_name": "Bash",
            "tool_input": {"command": ["rm", "-rf", "dist"]}, "turn_id": "x"}, "--agent", "codex")
check('"behavior": "allow"' in out, "codex permission")

out = hook({"hook_event_name": "BeforeAgent", "session_id": "gm", "cwd": str(APP), "prompt": "hi"}, "--agent", "gemini")
check(out == "{}", "gemini gets JSON on stdout")

log = Path(tempfile.gettempdir()) / "emba-codex-log.jsonl"
log.write_text(json.dumps({"payload": {"type": "token_count", "rate_limits": {
    "primary": {"used_percent": 82.0, "window_minutes": 300, "resets_at": 1}, "secondary": None}}}) + "\n")
hook({"hook_event_name": "Stop", "session_id": "cx", "cwd": str(APP), "transcript_path": str(log)}, "--agent", "codex")
time.sleep(0.5)
w = (state().get("limits", {}).get("codex") or {}).get("windows") or [{}]
check(w[0].get("used") == 82 and w[0].get("label") == "5 hours", f"codex usage read from its log ({w})")

emba("quit")
time.sleep(1)
start = time.time()
out = hook(req)
check(out == "" and time.time() - start < 3, f"no Emba: silent and quick ({time.time() - start:.2f}s)")
print("all end-to-end checks passed")
