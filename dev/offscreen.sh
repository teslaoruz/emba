#!/bin/sh
# Run a check against an Emba that draws nowhere: the Qt host on the offscreen
# platform, own socket and settings. Nothing shows up, the mouse is left alone.
#   sh dev/offscreen.sh sh dev/question_test.sh
cd "$(dirname "$0")/.."
export EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-off.sock"
T=$(mktemp -d); mkdir -p "$T/emba"; echo '{"plugins": []}' > "$T/emba/config.json"
export XDG_CONFIG_HOME=$T   # the CLI and the check use the same throwaway settings
export GH_CONFIG_DIR="${GH_CONFIG_DIR:-$HOME/.config/gh}"   # but your gh login
QT_QPA_PLATFORM=offscreen .venv/bin/python desktop/host.py > dev/offscreen.log 2>&1 &
sleep 4
"$@"
python3 bin/emba quit > /dev/null 2>&1
grep -iE "error|warning: qrc|is not a type|undefined" dev/offscreen.log | grep -v "Socket error" | head
