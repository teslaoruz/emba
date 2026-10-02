"""Send fake hook events to a running emba, for looking at it without Claude.

    python3 dev/fake.py start          two sessions, one working, one thinking
    python3 dev/fake.py ask            a permission request; prints emba's answer
    python3 dev/fake.py done           first session finishes
    python3 dev/fake.py limit 85       usage at 85 %
    python3 dev/fake.py many           six sessions across four agents
    python3 dev/fake.py end            all sessions end
"""
import json
import os
import socket
import sys

SOCK = os.environ.get("EMBA_SOCKET") or os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "emba.sock")
A = {"sid": "fake-a", "cwd": "/home/you/code/invoices", "pid": 1}
B = {"sid": "fake-b", "cwd": "/home/you/notes", "pid": 1}


def send(msg, wait=False):
    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    s.sendall((json.dumps(msg) + "\n").encode())
    if wait:
        s.settimeout(120)
        print(s.makefile().readline().strip() or "(closed without answer)")
    s.close()


cmd = sys.argv[1] if len(sys.argv) > 1 else "start"
if cmd == "start":
    send({**A, "ev": "SessionStart"})
    send({**B, "ev": "SessionStart"})
    send({**A, "ev": "UserPromptSubmit", "target": "fix the failing invoice test"})
    send({**A, "ev": "PreToolUse", "tool": "Edit", "target": "Invoice.swift"})
    send({**B, "ev": "UserPromptSubmit", "target": "summarise this week"})
elif cmd == "ask":
    send({**A, "ev": "PermissionRequest", "tool": "Bash", "id": "toolu_fake1",
          "target": "rm -rf build && npm test", "full": "rm -rf build && npm test -- --coverage", "always": True}, wait=True)
elif cmd == "done":
    send({**A, "ev": "Stop", "text": "Fixed the rounding bug in Invoice.total and added a regression test. All 48 tests pass."})
elif cmd == "limit":
    pct = int(sys.argv[2]) if len(sys.argv) > 2 else 85
    send({"ev": "Limits", "model": "Opus", "five_hour": {"used_percentage": pct, "resets_at": 1790900000},
          "seven_day": {"used_percentage": 41, "resets_at": 1791300000}})
elif cmd == "many":
    for i, (agent, cwd, work) in enumerate([("claude", "invoices", "Invoice.swift"), ("codex", "api", "server.py"),
                                            ("codex", "web", "App.tsx"), ("gemini", "docs", "intro.md"),
                                            ("opencode", "cli", "main.go"), ("claude", "notes", "week.md")]):
        m = {"sid": f"fake-m{i}", "agent": agent, "cwd": f"/home/you/code/{cwd}", "pid": 1}
        send({**m, "ev": "SessionStart"})
        send({**m, "ev": "PreToolUse", "tool": "Edit", "target": work})
elif cmd == "end":
    for sid in ["fake-a", "fake-b"] + [f"fake-m{i}" for i in range(6)]:
        send({"sid": sid, "ev": "SessionEnd"})
