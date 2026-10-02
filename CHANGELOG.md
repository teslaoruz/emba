# Changelog

## Unreleased

- Usage for every agent that reports it: Claude (status line) and Codex (its session logs).
- Every session of every agent in the overview; it scrolls, with an agent badge when mixed.
- Emba dances while music plays (Linux, MPRIS).
- Clicking outside the island closes it; clear drawn mic and screen icons that say what they do.
- Continue in terminal opens the terminal you used last.
- Fixed: `emba quit` under the autostart service restarted Emba; springs went unstable at low
  frame rates; the limit plugin event fired on every status line update.

## 0.1.0

First release.

- Emba, a red panda with moods: working, waiting, done, sleepy, hungry, listening and more.
- Watches Claude Code, Codex, Gemini CLI and opencode sessions.
- Answer permission requests from the island: allow, deny, always allow. The terminal prompt stays
  live; nothing is ever approved by a failure.
- Ask box on your own account (Claude, Codex, opencode, Gemini, Ollama), with follow-ups and
  "continue in terminal".
- Look at a part of the screen, or drop files on Emba, and ask about them.
- Optional local voice: shake to talk, "Hey Emba", spoken answers.
- Emba as a pet: pet, feed, play and nap, by gesture or voice.
- Follows desktop colours: Caelestia, pywal or a custom theme file.
- Plugins: commands on events, buttons, QML panels.
- Runs on Linux (Quickshell, or Qt), macOS and Windows (Qt).
