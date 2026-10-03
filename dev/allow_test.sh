#!/bin/sh
# A permission request answered with a real click on Allow (separate Emba, own socket).
#   sh dev/allow_test.sh [X_FROM_RIGHT] [Y]
cd "$(dirname "$0")/.."
read -r W X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.x) \(.y)"')
EOF
R=$((X + W))
to() { hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1; ydotool mousemove -x 1 -y 0 > /dev/null; ydotool mousemove -x -1 -y 0 > /dev/null; }
python3 bin/emba quit > /dev/null 2>&1
export EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-allow.sock"
T=$(mktemp -d); mkdir -p "$T/emba"; echo '{}' > "$T/emba/config.json"; export XDG_CONFIG_HOME=$T
qs -p . > dev/allow.log 2>&1 &
pid=$!
sleep 3
to $((R - 700)) $((Y + 500)); sleep 0.5
python3 dev/fake.py start
python3 dev/fake.py ask > dev/allow.answer &
sleep 2
grim -g "$((R - 480)),$Y 480x200" dev/al-1.png
to $((R - ${1:-157})) $((Y + ${2:-89})); sleep 0.6
grim -g "$((R - 480)),$Y 480x200" dev/al-2.png
ydotool click 0xC0 > /dev/null; sleep 1.2
grim -g "$((R - 480)),$Y 480x200" dev/al-3.png
echo "hook got: $(cat dev/allow.answer)"
python3 dev/fake.py end > /dev/null 2>&1
kill $pid
python3 dev/sheet.py dev/allow.png dev/al-1.png dev/al-2.png dev/al-3.png
