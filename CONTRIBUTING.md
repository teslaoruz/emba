# Contributing

Thanks for wanting to help. Bug reports, ideas, new agents, plugins and fixes are all welcome.

## Getting set up

```sh
git clone https://github.com/teslaoruz/emba && cd emba
```

- **Linux with a layer-shell compositor:** install [Quickshell](https://quickshell.org), then
  `qs -p .` runs Emba straight from the checkout. Edits to the `.qml` files reload on save.
- **Everywhere else:** `python -m venv .venv && .venv/bin/pip install PySide6`, then
  `.venv/bin/python desktop/host.py`.

## Layout

| Path | What |
|---|---|
| `App.qml` | sessions, permission requests, ask box, voice, plugins: all the logic |
| `Island.qml` | the island and its views |
| `Panda.qml` | Emba, drawn on a Canvas every frame |
| `Pet.qml` | hunger, sleep and play |
| `Theme.qml` | colours, from the desktop |
| `Settings.qml` | the settings page |
| `shell.qml` | the Quickshell window (Linux) |
| `desktop/` | the Qt host for Windows, macOS and X11, and the screen picker |
| `hook/emba-hook` | the hook every agent runs; standard-library Python |
| `hook/hooks.py` | connects and disconnects agents |
| `bin/emba` | the command line |
| `voice/voice.py` | local speech in and out |
| `integrations/opencode/` | the opencode plugin |
| `plugins/` | bundled plugins |

## Checks

```sh
python tests/test_e2e.py           # start Emba, drive it with real hook payloads
EMBA_HOST=qt python tests/test_e2e.py   # the same against the Qt host
sh dev/tour.sh                     # walk through every view and take screenshots (Linux)
```

CI runs the end-to-end test on Linux, macOS and Windows for every pull request.

## A few rules

- **Never let a failure approve something.** Anything that goes wrong in the hook must end with
  no output, so the agent falls back to its own prompt.
- **Never block an agent.** The hook gives up connecting after 0.3 s.
- **No shell for user or agent text.** Commands are argument lists.
- Keep the words plain. Emba is for people, not for log files.
- Match the style around you: small files, comments that say *why*.

## Adding an agent

1. Map its hook events to Emba's in `hook/emba-hook` (see the Gemini mapping).
2. Teach `hook/hooks.py` where its settings live and which events to add.
3. Add a payload case to `tests/test_e2e.py`.
