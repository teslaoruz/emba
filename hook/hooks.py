#!/usr/bin/env python3
"""Connect Emba to coding agents, or disconnect it. Standard library only.

    python3 hook/hooks.py install   [AGENT ...] [--statusline] [--yes]
    python3 hook/hooks.py uninstall [AGENT ...] [--yes]
    python3 hook/hooks.py status    prints {"claude": {...}, "codex": {...}, ...}

AGENT is claude, codex, gemini, agy (Antigravity) or opencode; default: every one installed.
Only Emba's own entries are touched. Each file gets a dated backup and the
diff is shown before anything is written.
"""

import difflib
import json
import os
import shlex
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOOK = HERE / "emba-hook"
PLUGIN = HERE.parent / "integrations" / "opencode" / "emba.js"
HOME = Path.home()


def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")


def hook_command(agent):
    if os.name == "nt":
        return f'"{sys.executable}" "{HOOK}" --agent {agent}'
    return f"{shlex.quote(str(HOOK))} --agent {agent}" if agent != "claude" else shlex.quote(str(HOOK))


def ours(entry):
    return any("emba-hook" in h.get("command", "") for h in entry.get("hooks", []))


def strip_hooks(cfg):
    hooks = cfg.get("hooks", {})
    for ev in list(hooks):
        hooks[ev] = [e for e in hooks[ev] if not ours(e)]
        if not hooks[ev]:
            del hooks[ev]
    if not hooks:
        cfg.pop("hooks", None)


def add_hooks(cfg, agent, events, timeout=None, blocking=(), blocking_timeout=None):
    hooks = cfg.setdefault("hooks", {})
    for ev in events:
        h = {"type": "command", "command": hook_command(agent)}
        if ev in blocking and blocking_timeout:
            h["timeout"] = blocking_timeout
        elif timeout:
            h["timeout"] = timeout
        if agent == "gemini":
            h["name"] = "emba"
        entry = {"hooks": [h]}
        if agent != "gemini" or ev in ("BeforeTool", "AfterTool"):
            entry = {"matcher": ".*", **entry}  # Gemini matches lifecycle events exactly; none = all
        hooks.setdefault(ev, []).append(entry)


def has_hooks(cfg):
    return any(ours(e) for v in cfg.get("hooks", {}).values() for e in v)


# ---- Claude Code: ~/.claude/settings.json ----

def claude_file():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or HOME / ".claude") / "settings.json"


def claude_install(cfg, statusline):
    claude_uninstall(cfg)
    add_hooks(cfg, "claude", ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "Notification",
                              "Stop", "PermissionRequest"], blocking=["PermissionRequest"], blocking_timeout=600)
    if statusline:
        old = cfg.get("statusLine", {}).get("command", "")
        cfg["statusLine"] = {"type": "command",
                             "command": f"{shlex.quote(str(HOOK))} statusline" + (f" {shlex.quote(old)}" if old else "")}


def claude_uninstall(cfg):
    strip_hooks(cfg)
    sl = cfg.get("statusLine", {})
    if "emba-hook" in sl.get("command", ""):
        wrapped = shlex.split(sl["command"])[2:]
        if wrapped:
            sl["command"] = wrapped[0]
        else:
            cfg.pop("statusLine")


# ---- Codex: ~/.codex/hooks.json, same events and output as Claude Code ----

def codex_install(cfg, _):
    strip_hooks(cfg)
    # timeouts in seconds; PermissionRequest waits for an answer
    add_hooks(cfg, "codex", ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop"],
              timeout=5, blocking=["PermissionRequest"], blocking_timeout=600)


# ---- Gemini CLI: ~/.gemini/settings.json ----

def gemini_install(cfg, _):
    strip_hooks(cfg)
    # timeouts in milliseconds; Gemini permissions are answered in its terminal
    add_hooks(cfg, "gemini", ["SessionStart", "SessionEnd", "BeforeAgent", "BeforeTool", "AfterAgent", "Notification"],
              timeout=5000)


# ---- Antigravity (agy): ~/.gemini/config/hooks.json, one named block per hook ----
# Watched only: agy decides its own permissions (an empty reply to PreToolUse is
# not documented the same everywhere), so its approvals stay in its terminal.

def agy_install(cfg, _):
    def h(ev):
        return {"type": "command", "command": f"{hook_command('agy')} --event {ev}", "timeout": 10}
    cfg["emba"] = {"PreInvocation": [h("PreInvocation")],
                   "PostToolUse": [{"matcher": "*", "hooks": [h("PostToolUse")]}],
                   "Stop": [h("Stop")]}


def agy_uninstall(cfg):
    cfg.pop("emba", None)


AGENTS = {
    "claude": dict(file=claude_file, install=claude_install, uninstall=claude_uninstall),
    "codex": dict(file=lambda: Path(os.environ.get("CODEX_HOME") or HOME / ".codex") / "hooks.json",
                  install=codex_install, uninstall=strip_hooks),
    "gemini": dict(file=lambda: HOME / ".gemini" / "settings.json", install=gemini_install, uninstall=strip_hooks),
    "agy": dict(file=lambda: HOME / ".gemini" / "config" / "hooks.json", install=agy_install, uninstall=agy_uninstall),
}
EVERY = list(AGENTS) + ["opencode"]


# ---- opencode: a plugin file, not a hook ----

def opencode_plugin():
    return config_home() / "opencode" / "plugins" / "emba.js"


def installed(agent):
    return bool(shutil.which(agent)) or (agent == "claude" and claude_file().parent.exists())


def status():
    out = {}
    for name, a in AGENTS.items():
        try:
            cfg = json.loads(a["file"]().read_text())
        except (OSError, ValueError):
            cfg = {}
        out[name] = {"installed": installed(name), "connected": "emba" in cfg if name == "agy" else has_hooks(cfg)}
        if name == "claude":
            out[name]["statusline"] = "emba-hook" in cfg.get("statusLine", {}).get("command", "")
    out["opencode"] = {"installed": installed("opencode"), "connected": opencode_plugin().exists()}
    return out


def write(path, before, after, yes):
    if after == before:
        print(f"{path}: already up to date")
        return
    sys.stdout.writelines(difflib.unified_diff(before.splitlines(True), after.splitlines(True), str(path), "new"))
    if not yes and input(f"\nWrite {path}? [y/N] ").strip().lower() != "y":
        print("skipped")
        return
    if path.exists():
        backup = path.with_name(f"{path.name}.bak-emba-{time.strftime('%Y%m%d-%H%M%S')}")
        shutil.copy2(path, backup)
        print(f"backup: {backup}")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(after)
    tmp.replace(path)
    print(f"wrote {path}")


def apply(agent, action, statusline, yes):
    if agent == "opencode":
        dst = opencode_plugin()
        if action == "install":
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(PLUGIN, dst)
            print(f"installed {dst}")
        elif dst.exists():
            dst.unlink()
            print(f"removed {dst}")
        return
    a = AGENTS[agent]
    path = a["file"]()
    before = path.read_text() if path.exists() else "{}\n"
    try:
        cfg = json.loads(before)
    except ValueError as e:
        print(f"{path} is not valid JSON ({e}); left alone")
        return
    if action == "install":
        a["install"](cfg, statusline)
    else:
        a["uninstall"](cfg)
    after = json.dumps(cfg, indent=2) + "\n"
    if action == "uninstall" and not cfg and not path.exists():
        return
    write(path, before, after, yes)


def main():
    args = sys.argv[1:]
    if args[:1] == ["status"]:
        print(json.dumps(status()))
        return
    if not args or args[0] not in ("install", "uninstall"):
        sys.exit(__doc__)
    names = [a for a in args[1:] if not a.startswith("--")]
    unknown = [n for n in names if n not in EVERY + ["all"]]
    if unknown:
        sys.exit(f"unknown agent: {', '.join(unknown)} (choose from {', '.join(EVERY)})")
    if not names:
        names = [n for n in EVERY if installed(n)] if args[0] == "install" else EVERY
    elif "all" in names:
        names = EVERY
    if not names:
        sys.exit("no supported agent found (claude, codex, gemini, agy, opencode)")
    for n in names:
        apply(n, args[0], "--statusline" in args, "--yes" in args)
    if args[0] == "install":
        print("Restart running agent sessions so they pick up the change.")


if __name__ == "__main__":
    main()
