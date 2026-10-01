# Security

Emba sits between coding agents and the commands they want to run, so security reports matter a
lot. If you find a way to make Emba approve something the user did not approve, run a command
from agent output, or read the socket as another user, please report it privately through
[GitHub security advisories](https://github.com/teslaoruz/emba/security/advisories/new) rather
than a public issue.

What Emba promises:

- A permission is only granted by a click (or <kbd>Y</kbd> after clicking the island). Voice can
  only point at a button.
- Any failure in the hook ends with no output, which leaves the decision to the agent's own prompt.
- Plugin and action commands are argument lists, never passed through a shell.
- The socket lives in a per-user directory (`$XDG_RUNTIME_DIR`, the macOS temp dir, or a named
  pipe restricted to the user on Windows).
