#!/bin/sh
# Install emba for the current user.
#   ./install.sh                 link the config, add the Claude Code hooks
#   ./install.sh --statusline    also show usage limits (wraps your statusline)
#   ./install.sh --service       also start emba now and at every login (systemd)
#   ./install.sh --uninstall     undo all of it
set -eu
here=$(cd "$(dirname "$0")" && pwd)
qsdir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
unitdir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

for dep in qs python3; do
    command -v $dep > /dev/null || { echo "emba needs '$dep' (quickshell, python3)"; exit 1; }
done

case " $* " in
*" --uninstall "*)
    python3 "$here/hook/hooks.py" uninstall
    if [ -f "$unitdir/emba.service" ]; then
        systemctl --user disable --now emba.service || true
        rm -f "$unitdir/emba.service"
    fi
    [ -L "$qsdir/emba" ] && rm "$qsdir/emba"
    echo "emba removed. Your config in ~/.config/emba is left alone."
    exit 0
    ;;
esac

mkdir -p "$qsdir"
if [ -e "$qsdir/emba" ] && [ ! -L "$qsdir/emba" ]; then
    echo "$qsdir/emba exists and is not a link to this checkout; move it first"
    exit 1
fi
ln -sfn "$here" "$qsdir/emba"
echo "linked $qsdir/emba -> $here"

case " $* " in *" --statusline "*) sl=--statusline ;; *) sl= ;; esac
python3 "$here/hook/hooks.py" install $sl

case " $* " in
*" --service "*)
    mkdir -p "$unitdir"
    cp "$here/emba.service" "$unitdir/"
    systemctl --user daemon-reload
    systemctl --user enable --now emba.service
    echo "emba is running and starts with your session"
    ;;
*)
    echo
    echo "Start it:  qs -c emba"
    echo "Autostart: ./install.sh --service, or add 'qs -c emba' to your compositor's autostart"
    ;;
esac
