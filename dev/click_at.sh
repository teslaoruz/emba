#!/bin/sh
# Click a point while a decoy window holds focus:  sh dev/click_at.sh DECOY X Y OUT
cd "$(dirname "$0")/.."
python3 bin/emba focus "$1" > /dev/null; sleep 0.3
[ "$(hyprctl activewindow -j | jq -r .address)" = "$1" ] || { echo "ABORT: decoy not focused"; exit 1; }
hyprctl dispatch "hl.dsp.cursor.move({x=$2,y=$3})" > /dev/null 2>&1
ydotool mousemove -x 1 -y 0 > /dev/null; sleep 0.1; ydotool mousemove -x -1 -y 0 > /dev/null; sleep 0.2
ydotool click 0xC0 > /dev/null; sleep 1
grim -g "1420,0 500x200" "$4"
