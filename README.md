<div align="center">

<img src="assets/emba-256.png" width="128" alt="Emba, a red panda">

# Emba

**A little red panda that keeps an eye on your coding agents.**

Approve what they want to run without going back to the terminal, see what each one is doing,
and get a small cheer when they finish. For Claude Code, Codex, Gemini CLI and opencode.

[![CI](https://github.com/teslaoruz/emba/actions/workflows/ci.yml/badge.svg)](https://github.com/teslaoruz/emba/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-e2683c)](LICENSE)
![Linux · macOS · Windows](https://img.shields.io/badge/runs%20on-Linux%20·%20macOS%20·%20Windows-3a2420)

<img src="docs/demo.gif" width="500" alt="Emba noticing a session, asking for permission, and celebrating when it is done">

</div>

## What it does

- **Answer permission requests from anywhere.** When an agent wants to run a command or edit a
  file, Emba pops up with exactly what it wants to do. Allow, deny, or always allow. The terminal
  prompt stays live too; whichever you answer first wins.
- **See every session at a glance.** What each agent is doing right now, in plain words.
  Click a session to jump to its terminal.
- **Know when it's done.** Emba flips, sparkles and shows the last reply.
- **Ask a quick question.** A small ask box that uses the agent you already have, on your own
  account: no API keys. Pick who answers: Claude, Codex, opencode, Gemini, or a local Ollama model.
  Follow up in place, or continue the conversation in the agent's own terminal.
- **Show it your screen.** Drag a rectangle anywhere and ask about what's in it.
- **Feed it files.** Drop a file on Emba to ask about it.
- **Talk to it** (optional). Shake the mouse or say "Hey Emba", ask out loud, hear the answer.
  Speech is recognised and spoken on your computer; nothing is sent anywhere.
- **Look after it.** Emba gets hungry, sleepy and a bit lonely. Rub the cursor over it to pet it,
  double-click to feed it bamboo, click the island to throw it a ball, hold it to tuck it in.
- **Make it yours.** It follows your desktop's colours (Caelestia, pywal, or your own), sits in
  any corner, and can be extended with plugins.

<div align="center">
<img src="docs/moods.png" width="760" alt="Emba's moods: idle, working, waiting, done, error, hungry, sleepy, listening, love, dizzy">
<br><br>
<img src="docs/views.png" width="760" alt="The island: a permission request, the sessions overview, a finished task, hovering the corner, and the small pill">
</div>

## Install

**Linux and macOS**

```sh
curl -fsSL https://raw.githubusercontent.com/teslaoruz/emba/main/install.sh | sh
```

**Windows** (PowerShell)

```powershell
irm https://raw.githubusercontent.com/teslaoruz/emba/main/install.ps1 | iex
```

**Arch Linux**: build the package from [`packaging/aur`](packaging/aur/PKGBUILD) with `makepkg -si`.

The installer asks before connecting any agent and shows you every change it makes to an agent's
settings; each file gets a backup first. Nothing needs admin rights. To remove everything later:
`./install.sh --uninstall` (or `install.ps1 --uninstall`).

On Wayland desktops with layer-shell (Hyprland, Sway, niri, KDE…) Emba runs on
[Quickshell](https://quickshell.org) and sits right on the edge of the screen. Everywhere else
(Windows, macOS, GNOME, X11) the same interface runs on Qt.

## Agents

| Agent | Watch sessions | Answer permissions from Emba | Ask box |
|---|:-:|:-:|:-:|
| Claude Code | ✓ | ✓ | ✓ |
| Codex | ✓ | ✓ | ✓ |
| opencode | ✓ | ✓ (first 30 s, then the terminal) | ✓ |
| Gemini CLI | ✓ | points you to the terminal | ✓ |
| Ollama | | | ✓ |

Connect any or all of them in **Settings → Agents**, or with `emba connect`.

**Free options.** Emba itself is free and open source. For the ask box you can use Gemini CLI's
free tier, opencode's free models, or a model running on your own machine with Ollama.

## Using it

| | |
|---|---|
| Open or close | hover the island, or `emba toggle` |
| Allow / deny | click, or press <kbd>Y</kbd> / <kbd>N</kbd> after clicking the island |
| Ask | click "Ask…", or `emba ask "your question"` |
| Ask about the screen | ⛶ in the ask box, or `emba look` |
| Talk | shake the mouse, say "Hey Emba", or `emba listen` |
| Settings | the ⚙ on the island, or `emba settings` |

Voice commands for Emba itself: *"eat"*, *"play"*, *"go to sleep"*, *"wake up"*,
*"look at my screen"*, *"settings"*. Saying *"allow"* while a request is open only highlights the
button: voice never approves anything on its own.

<details>
<summary><b>All settings</b></summary>

Everything is in the settings window. Behind it is a plain file,
`~/.config/emba/config.json` (Windows: `%APPDATA%\emba\config.json`), which also takes:

| Key | Default | |
|---|---|---|
| `position` | `top-right` | `top-left` `top` `top-right` `left` `right` `bottom-left` `bottom` `bottom-right` |
| `marginX`, `marginY` | `12`, `8` | distance from the screen edge |
| `scale` | `1` | |
| `color` | `#e2683c` | Emba's fur |
| `theme` | `auto` | `auto` `caelestia` `pywal` `custom` `default` |
| `askWith` | `auto` | `claude` `gemini` `opencode` `codex` `ollama` |
| `askModel` | | model for the ask box |
| `focusCommand` | | command to focus a session's terminal; `{window}` `{pid}` `{cwd}` are filled in |
| `limitWarn` | `80` | warn at this % of a Claude usage limit |

`emba set KEY VALUE` changes one from the command line.
A custom theme is a `~/.config/emba/theme.json` with any of `base surface text dim primary ok warn
error`… as hex colours; point matugen or wallust at it.

</details>

<details>
<summary><b>Command line</b></summary>

```
emba                     start (in the background)
emba settings            open settings
emba ask "question"      ask, and show the answer
emba look                drag a rectangle on screen and ask about it
emba listen              talk to Emba
emba allow | deny        answer the oldest permission request
emba feed | play | nap   look after Emba
emba connect [AGENT]     connect claude, codex, gemini, opencode (shows each change first)
emba disconnect [AGENT]
emba autostart on|off
emba doctor              check everything Emba needs
emba plugins [new NAME]  list plugins, or start your own
```

</details>

## Plugins

A plugin is a folder with a `plugin.json`. It can run a command when something happens (a session
finishes, an agent asks for permission…), add buttons, or show its own little panel. Three come
with Emba: desktop notifications, "open in editor / folder", and a session timer.

```sh
emba plugins new my-plugin   # creates ~/.config/emba/plugins/my-plugin/plugin.json
```

See **[PLUGINS.md](PLUGINS.md)** for everything a plugin can do.

## Privacy and safety

- Emba never blocks your agents. If it isn't running, the hook exits in milliseconds and prints
  nothing.
- Every failure (a crash, a timeout, a restart) falls back to the agent's normal terminal prompt.
  Nothing is ever approved by accident.
- Keyboard shortcuts only work after you click the island, so typing in a terminal can't approve
  something by mistake.
- No telemetry, no accounts, no keys. Emba talks to your agents over a local socket only your user
  can open. Voice runs entirely on your computer.

## How it works

```
your agent ─ hook ─► hook/emba-hook ── local socket ──► Emba
                          ▲                               │
                          └──── allow / deny ─────────────┘
```

The hook is one standard-library Python file that turns each agent's events into the same small
messages. The interface is QML, written once: on Linux it runs on Quickshell, elsewhere
`desktop/host.py` runs the very same files on Qt (PySide6).

## Contributing

Bug reports, ideas and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

```sh
git clone https://github.com/teslaoruz/emba && cd emba
qs -p .                      # run from the checkout (or: python desktop/host.py)
python tests/test_e2e.py     # end-to-end check against a running Emba
```

## Credits

Inspired by [coucou](https://github.com/louis-CFM/coucou) by Louis Raillé, a notch companion for
Claude Code on macOS. Emba is its own code and its own character.

Not affiliated with Anthropic, OpenAI, Google or SST. Claude, Codex, Gemini and opencode are
trademarks of their owners.

[MIT licensed](LICENSE).
