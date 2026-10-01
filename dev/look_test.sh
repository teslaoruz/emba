#!/bin/sh
# `emba look` with the real mouse: draw a rectangle with slurp via ydotool.
#   sh dev/look_test.sh X1 Y1 X2 Y2
cd "$(dirname "$0")/.."
to() { hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1 || hyprctl dispatch movecursor "$1" "$2" > /dev/null; }
python3 bin/emba look &
for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x slurp > /dev/null && break; sleep 0.5; done
sleep 0.5                                   # slurp is up
to "$1" "$2"; sleep 0.3
ydotool click 0x40 > /dev/null; sleep 0.2
to $((($1 + $3) / 2)) $((($2 + $4) / 2)); sleep 0.15
to "$3" "$4"; sleep 0.3
ydotool click 0x80 > /dev/null
wait
sleep 1.5
read -r W X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.x) \(.y)"')
EOF
grim -g "$((X + W - 500)),$Y 500x230" dev/look1.png
ls -t "${TMPDIR:-/tmp}/emba-$(id -un)/" | head -1
