#!/bin/sh
# Install perch for the current user.
#   ./install.sh                 link the config, add the Claude Code hooks
#   ./install.sh --statusline    also show usage limits (wraps your statusline)
#   ./install.sh --service       also start perch now and at every login (systemd)
#   ./install.sh --uninstall     undo all of it
set -eu
here=$(cd "$(dirname "$0")" && pwd)
qsdir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
unitdir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

for dep in qs python3; do
    command -v $dep > /dev/null || { echo "perch needs '$dep' (quickshell, python3)"; exit 1; }
done

case " $* " in
*" --uninstall "*)
    python3 "$here/hook/hooks.py" uninstall
    if [ -f "$unitdir/perch.service" ]; then
        systemctl --user disable --now perch.service || true
        rm -f "$unitdir/perch.service"
    fi
    [ -L "$qsdir/perch" ] && rm "$qsdir/perch"
    echo "perch removed. Your config in ~/.config/perch is left alone."
    exit 0
    ;;
esac

mkdir -p "$qsdir"
if [ -e "$qsdir/perch" ] && [ ! -L "$qsdir/perch" ]; then
    echo "$qsdir/perch exists and is not a link to this checkout; move it first"
    exit 1
fi
ln -sfn "$here" "$qsdir/perch"
echo "linked $qsdir/perch -> $here"

case " $* " in *" --statusline "*) sl=--statusline ;; *) sl= ;; esac
python3 "$here/hook/hooks.py" install $sl

case " $* " in
*" --service "*)
    mkdir -p "$unitdir"
    cp "$here/perch.service" "$unitdir/"
    systemctl --user daemon-reload
    systemctl --user enable --now perch.service
    echo "perch is running and starts with your session"
    ;;
*)
    echo
    echo "Start it:  qs -c perch"
    echo "Autostart: ./install.sh --service, or add 'qs -c perch' to your compositor's autostart"
    ;;
esac
