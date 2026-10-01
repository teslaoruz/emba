#!/bin/sh
# Drag a file from dev/dragsource.py onto Emba with the real mouse (ydotool),
# screenshotting the hover, the drop and the result.
#   sh dev/drag_test.sh FROM_X FROM_Y
cd "$(dirname "$0")/.."
to() { hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1 || hyprctl dispatch movecursor "$1" "$2" > /dev/null; }
read -r W X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.x) \(.y)"')
EOF
geo="$((X + W - 500)),$Y 500x230"
fx=$1 fy=$2
cx=$((X + W - 8)) cy=$((Y + 6))

to "$fx" "$fy"; sleep 0.4
ydotool click 0x40 > /dev/null; sleep 0.3          # press
i=1
while [ $i -le 12 ]; do
    to $((fx + (cx - fx) * i / 12)) $((fy + (cy - fy) * i / 12)); sleep 0.08
    i=$((i + 1))
done
sleep 0.8
to $((cx - 40)) $((cy + 24)); sleep 0.8
grim -g "$geo" dev/drop1.png                        # hovering with the file
to $((cx - 70)) $((cy + 30)); sleep 0.4
ydotool click 0x80 > /dev/null                      # release
sleep 0.25; grim -g "$geo" dev/drop2.png
sleep 1.2; grim -g "$geo" dev/drop3.png
python3 dev/sheet.py dev/drop.png dev/drop1.png dev/drop2.png dev/drop3.png
