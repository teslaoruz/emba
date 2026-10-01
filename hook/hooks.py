#!/usr/bin/env python3
"""Add or remove emba's hooks in ~/.claude/settings.json.

    python3 hook/hooks.py install [--statusline] [--yes]
    python3 hook/hooks.py uninstall [--yes]
    python3 hook/hooks.py status          prints {"hooks": bool, "statusline": bool}

Only emba's own entries are touched; everything else in the file is kept.
A dated backup is written first, and the diff is shown before saving.
"""

import difflib
import json
import os
import shlex
import shutil
import sys
import time
from pathlib import Path

SETTINGS = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude") / "settings.json"
HOOK = str(Path(__file__).resolve().parent / "emba-hook")
EVENTS = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "PermissionRequest"]


def ours(entry):
    return any("emba-hook" in h.get("command", "") for h in entry.get("hooks", []))


def strip(cfg):
    hooks = cfg.get("hooks", {})
    for ev in list(hooks):
        hooks[ev] = [e for e in hooks[ev] if not ours(e)]
        if not hooks[ev]:
            del hooks[ev]
    if not hooks:
        cfg.pop("hooks", None)
    sl = cfg.get("statusLine", {})
    cmd = sl.get("command", "")
    if "emba-hook" in cmd:
        wrapped = shlex.split(cmd)[2:]
        if wrapped:
            sl["command"] = wrapped[0]
        else:
            cfg.pop("statusLine")


def install(cfg, statusline):
    strip(cfg)
    hooks = cfg.setdefault("hooks", {})
    for ev in EVENTS:
        h = {"type": "command", "command": shlex.quote(HOOK)}
        if ev == "PermissionRequest":
            h["timeout"] = 600
        hooks.setdefault(ev, []).append({"matcher": ".*", "hooks": [h]} if ev in ("PreToolUse", "PermissionRequest", "Notification") else {"hooks": [h]})
    if statusline:
        old = cfg.get("statusLine", {}).get("command", "")
        cfg["statusLine"] = {"type": "command",
                             "command": f"{shlex.quote(HOOK)} statusline" + (f" {shlex.quote(old)}" if old else "")}


def main():
    args = sys.argv[1:]
    if args[:1] == ["status"]:
        try:
            cfg = json.loads(SETTINGS.read_text())
        except (OSError, ValueError):
            cfg = {}
        print(json.dumps({"hooks": any(ours(e) for v in cfg.get("hooks", {}).values() for e in v),
                          "statusline": "emba-hook" in cfg.get("statusLine", {}).get("command", "")}))
        return
    if not args or args[0] not in ("install", "uninstall"):
        sys.exit(__doc__)
    before = SETTINGS.read_text() if SETTINGS.exists() else "{}\n"
    try:
        cfg = json.loads(before)
    except ValueError as e:
        sys.exit(f"{SETTINGS} is not valid JSON ({e}); fix it first, nothing was changed")
    if args[0] == "install":
        install(cfg, "--statusline" in args)
    else:
        strip(cfg)
    after = json.dumps(cfg, indent=2) + "\n"
    if after == before:
        print("settings.json already up to date")
        return
    sys.stdout.writelines(difflib.unified_diff(before.splitlines(True), after.splitlines(True), str(SETTINGS), "new"))
    if "--yes" not in args and input("\nWrite this? [y/N] ").strip().lower() != "y":
        print("nothing written")
        return
    if SETTINGS.exists():
        backup = SETTINGS.with_name(f"settings.json.bak-emba-{time.strftime('%Y%m%d-%H%M%S')}")
        shutil.copy2(SETTINGS, backup)
        print(f"backup: {backup}")
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    tmp = SETTINGS.with_suffix(".tmp")
    tmp.write_text(after)
    tmp.replace(SETTINGS)
    print(f"wrote {SETTINGS}; new Claude Code sessions pick it up")


if __name__ == "__main__":
    main()
