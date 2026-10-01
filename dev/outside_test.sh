#!/bin/sh
# Real mouse and keyboard, made safe by a decoy terminal running `cat`:
# hover the corner, click the ask field, type, then click outside.
#   sh dev/outside_test.sh DECOY_ADDRESS
cd "$(dirname "$0")/.."
decoy=$1
to() { hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1; ydotool mousemove -x 1 -y 0 > /dev/null; sleep 0.1; ydotool mousemove -x -1 -y 0 > /dev/null; }
guard() { [ "$(hyprctl activewindow -j | jq -r .address)" = "$decoy" ] || { echo "ABORT: focus moved off the decoy"; exit 1; }; }
grab() { grim -g "1420,0 500x200" "dev/o-$1.png"; }

python3 bin/emba close > /dev/null
python3 bin/emba focus "$decoy"; sleep 0.5; guard
to 600 500; sleep 1
to 1916 3; sleep 1.6; grab 1-hovered                 # hover the corner: it opens
f=$(python3 bin/emba state > /dev/null; echo)
to 1700 "${ASK_Y:-90}"; sleep 0.4
ydotool click 0xC0 > /dev/null; sleep 1; grab 2-clicked   # click the ask field
guard
wtype "hello there"; sleep 0.6; grab 3-typed
to 400 600; sleep 0.4
ydotool click 0xC0 > /dev/null; sleep 1; grab 4-outside   # click somewhere else
d=$(hyprctl clients -j | jq -r --arg a "$decoy" '.[] | select(.address == $a) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
grim -g "$d" dev/o-decoy.png
python3 dev/sheet.py dev/outside.png dev/o-1-hovered.png dev/o-2-clicked.png dev/o-3-typed.png dev/o-4-outside.png
echo done
