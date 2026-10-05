#!/bin/sh
# What you actually see: grim frames of the top-right corner while the real
# mouse hovers in from nowhere, rests, and leaves (separate Emba, own socket).
#   sh dev/screenrec.sh [start]   ("start": a fake session runs, so the pill shows)
cd "$(dirname "$0")/.."
read -r W X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.x) \(.y)"')
EOF
R=$((X + W))
out=$PWD/dev/sr; rm -rf "$out"; mkdir -p "$out"
export EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-sr.sock"
T=$(mktemp -d); mkdir -p "$T/emba"; echo '{"plugins": []}' > "$T/emba/config.json"; export XDG_CONFIG_HOME=$T
to() { hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1; ydotool mousemove -x 1 -y 0 > /dev/null; ydotool mousemove -x -1 -y 0 > /dev/null; }
grab() { n=0; while [ $n -lt "$1" ]; do grim -g "$((R - 520)),$Y 520x400" "$out/$(printf %s-%03d "$2" $n).png"; n=$((n + 1)); done; }
to $((R - 900)) $((Y + 600))
qs -p . > "$out/qs.log" 2>&1 &
QS=$!
sleep "${WAIT:-4.5}"
[ "$1" = start ] && python3 dev/fake.py start > /dev/null 2>&1 && sleep 1.5
grab ${N:-50} in &
i=1; while [ $i -le 10 ]; do to $((R - 200 + (200 - ${TX:-3}) * i / 10)) $((Y + 200 - (200 - ${TY:-20}) * i / 10)); sleep 0.025; i=$((i + 1)); done
wait $!
grab 60 out &
sleep 0.3; to $((R - 900)) $((Y + 600))
wait $!
python3 dev/fake.py end > /dev/null 2>&1
python3 bin/emba quit > /dev/null 2>&1; kill $QS 2> /dev/null
ls "$out" | wc -l
