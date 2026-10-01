#!/bin/sh
# Real typing into Emba's ask box, safely: a decoy terminal running `cat` must
# have focus, so any keys that miss Emba land there and nowhere else.
#   sh dev/type_test.sh DECOY_ADDRESS
cd "$(dirname "$0")/.."
decoy=$1
guard() { [ "$(hyprctl activewindow -j | jq -r .address)" = "$decoy" ] || { echo "ABORT: focus moved off the decoy"; exit 1; }; }
grab() { grim -g "1420,0 500x200" "dev/$1.png"; }

python3 bin/emba focus "$decoy"; sleep 0.4; guard
python3 bin/emba open > /dev/null; sleep 1.4; grab k0
hyprctl dispatch "hl.dsp.cursor.move({x=1700,y=141})" > /dev/null 2>&1; sleep 0.5
ydotool mousemove -x 2 -y 0 > /dev/null; sleep 0.1; ydotool mousemove -x -2 -y 0 > /dev/null; sleep 0.3   # real motion, like a hand
ydotool click 0xC0 > /dev/null; sleep 1; grab k1
guard
wtype "hello there"; sleep 0.5; grab k2
wtype -k Escape; sleep 0.6; grab k3
d=$(hyprctl clients -j | jq -r --arg a "$decoy" '.[] | select(.address == $a) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
grim -g "$d" dev/k-decoy.png
python3 dev/sheet.py dev/typing.png dev/k0.png dev/k1.png dev/k2.png dev/k3.png
echo done
