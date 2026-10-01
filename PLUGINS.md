# Writing a plugin

A plugin is a folder with a `plugin.json` in it:

- your own: `~/.config/emba/plugins/<name>/` (Windows: `%APPDATA%\emba\plugins\<name>\`)
- bundled with Emba: [`plugins/`](plugins)

Start one with `emba plugins new my-plugin`, then turn it on in **Settings → Plugins**.
Emba picks up changes the next time settings are opened or Emba restarts.

A plugin can do any mix of three things.

## 1. Run a command when something happens

```json
{
  "name": "Say it out loud",
  "description": "Speaks when a session finishes.",
  "events": {
    "finished": ["spd-say", "{name} is done"]
  }
}
```

| Event | When | Placeholders |
|---|---|---|
| `session_start` | an agent session starts | `{name}` `{cwd}` `{agent}` |
| `finished` | a session finishes its turn | `{name}` `{cwd}` `{agent}` `{text}` (the last reply) |
| `permission` | an agent asks before doing something | `{name}` `{cwd}` `{agent}` `{tool}` `{command}` |
| `limit` | Claude usage crosses your warning level | `{window}` `{percent}` |

`{plugin}` is always the plugin's own folder, handy for shipping a script with it.

A command is a list: the program, then its arguments. Placeholders fill in whole arguments and no
shell is involved, so text from an agent can never turn into a command. If you need a shell, call
a script you ship: `["sh", "{plugin}/on-finish.sh", "{name}"]`.

To use different commands per system, give an object instead of a list:

```json
"finished": {
  "linux":   ["notify-send", "{name} is done"],
  "darwin":  ["osascript", "-e", "on run argv", "-e", "display notification (item 1 of argv)", "-e", "end run", "{name} is done"],
  "windows": ["powershell", "-File", "{plugin}/notify.ps1", "{name} is done"]
}
```

## 2. Add buttons

```json
"actions": [
  { "label": "Editor", "run": ["code", "{cwd}"] },
  { "label": "Git log", "run": ["sh", "{plugin}/gitlog.sh", "{cwd}"] }
]
```

They show up for the session when it finishes. Placeholders: `{cwd}` `{name}` `{agent}` `{plugin}`.

## 3. Show a little panel

```json
"qml": "View.qml"
```

`View.qml` is any QML item. Emba shows it in the island's overview and sets two properties on it:

- `app`: sessions (`app.sessions`), usage (`app.limits`), `app.ask(text, files)`, and more; see
  [`App.qml`](App.qml)
- `theme`: the current colours (`theme.text`, `theme.dim`, `theme.surface`, `theme.primary`…)

```qml
import QtQuick

Text {
    property var app
    property var theme

    text: `${app?.sessions.length ?? 0} sessions`
    color: theme?.dim ?? "gray"
}
```

[`plugins/session-timer`](plugins/session-timer) is a complete example.

## Sharing

Put the folder in a git repository. Others clone it into their plugins folder and turn it on.
