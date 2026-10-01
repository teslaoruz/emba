#!/bin/sh
# Install Emba on Linux or macOS, for the current user. Nothing needs root.
#
#   curl -fsSL https://raw.githubusercontent.com/teslaoruz/emba/main/install.sh | sh
#   ./install.sh               (from a checkout)
#   ./install.sh --uninstall
#
# What it does: puts Emba in ~/.local/share/emba (or uses this checkout),
# adds an `emba` command to ~/.local/bin, a menu entry on Linux, and then asks
# before connecting any coding agent.
set -eu

REPO="https://github.com/teslaoruz/emba"
OS=$(uname -s)
say() { printf '\033[1;38;5;209m●\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

here=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")
if [ -n "$here" ] && [ -f "$here/App.qml" ]; then
    APP=$here
    checkout=1
else
    APP="${EMBA_HOME:-$HOME/.local/share/emba}"
    checkout=0
fi
BIN="$HOME/.local/bin"
LAUNCHER="$BIN/emba"

# ---------------------------------------------------------------- uninstall
if [ "${1:-}" = "--uninstall" ]; then
    if [ -x "$LAUNCHER" ]; then
        "$LAUNCHER" disconnect all < /dev/null || true
        "$LAUNCHER" autostart off || true
        "$LAUNCHER" quit || true
    fi
    rm -f "$LAUNCHER" "$HOME/.local/share/applications/emba.desktop" \
        "$HOME/.local/share/icons/hicolor/scalable/apps/emba.svg"
    [ "$checkout" = 0 ] && rm -rf "$APP"
    say "Emba is gone. Your settings in ~/.config/emba are still there if you come back."
    exit 0
fi

# ---------------------------------------------------------------- python
PY=$(command -v python3 || true)
[ -n "$PY" ] || die "Emba needs Python 3.9 or newer. Install it, then run this again."
"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || die "Emba needs Python 3.9 or newer."

# ---------------------------------------------------------------- the app
if [ "$checkout" = 0 ]; then
    if [ -d "$APP/.git" ]; then
        say "Updating Emba"
        git -C "$APP" pull --ff-only --quiet
    elif command -v git > /dev/null; then
        say "Downloading Emba"
        git clone --quiet --depth 1 "$REPO" "$APP"
    else
        say "Downloading Emba"
        mkdir -p "$APP"
        curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$APP" --strip-components 1
    fi
fi

# Wayland desktops with layer-shell get the Quickshell build; everything else
# (macOS, GNOME, X11) runs the same UI on Qt through PySide6.
quickshell=0
if [ "$OS" = Linux ] && [ -n "${WAYLAND_DISPLAY:-}" ] && command -v qs > /dev/null; then
    case "${XDG_CURRENT_DESKTOP:-}" in *GNOME* | *gnome*) ;; *) quickshell=1 ;; esac
fi

RUNPY=$PY
if [ "$quickshell" = 0 ]; then
    if ! "$PY" -c 'import PySide6' 2> /dev/null; then
        say "Setting up Qt (one time, about 200 MB)"
        [ -d "$APP/.venv" ] || "$PY" -m venv "$APP/.venv"
        "$APP/.venv/bin/python" -m pip install --quiet --upgrade pip PySide6
        RUNPY="$APP/.venv/bin/python"
    fi
fi

# ---------------------------------------------------------------- command + menu entry
mkdir -p "$BIN"
cat > "$LAUNCHER" << EOF
#!/bin/sh
exec "$RUNPY" "$APP/bin/emba" "\$@"
EOF
chmod +x "$LAUNCHER" "$APP/bin/emba" "$APP/hook/emba-hook"

if [ "$OS" = Linux ]; then
    mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/scalable/apps"
    cp "$APP/assets/emba.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/emba.svg"
    sed "s|^Exec=emba|Exec=$LAUNCHER|" "$APP/assets/emba.desktop" > "$HOME/.local/share/applications/emba.desktop"
fi

case ":$PATH:" in *":$BIN:"*) ;; *) say "Add $BIN to your PATH to use the emba command." ;; esac

# ---------------------------------------------------------------- connect, start
# Read answers from the terminal even when this script came through a pipe.
if (exec < /dev/tty) 2> /dev/null; then
    say "Connecting to your coding agents (you'll see each change first)"
    "$LAUNCHER" connect < /dev/tty || true
    printf 'Start Emba when you log in? [Y/n] '
    read -r answer < /dev/tty || answer=n
    case "$answer" in [nN]*) ;; *) "$LAUNCHER" autostart on ;; esac
fi
"$LAUNCHER" start
say "Done. Emba is in the corner of your screen. Try: emba settings"
