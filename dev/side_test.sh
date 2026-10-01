#!/bin/sh
# Look at Emba on a side edge, in a separate instance with its own settings.
#   sh dev/side_test.sh right|left
cd "$(dirname "$0")/.."
side=${1:-right}
T=$(mktemp -d)
mkdir -p "$T/emba"
printf '{"position": "%s"}\n' "$side" > "$T/emba/config.json"
export XDG_CONFIG_HOME=$T EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-side.sock"
qs -p . > dev/side.log 2>&1 &
pid=$!
sleep 3
read -r W H X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height) \(.x) \(.y)"')
EOF
if [ "$side" = right ]; then gx=$((X + W - 500)); else gx=$X; fi
geo="$gx,$((Y + H / 2 - 200)) 500x400"
python3 dev/fake.py start
sleep 1.5; grim -g "$geo" dev/side-compact.png
python3 bin/emba open > /dev/null; sleep 1.5; grim -g "$geo" dev/side-open.png
python3 bin/emba close > /dev/null; python3 dev/fake.py end; sleep 1.2; grim -g "$geo" dev/side-hidden.png
kill $pid
python3 dev/sheet.py dev/side.png dev/side-compact.png dev/side-open.png dev/side-hidden.png
grep -iE "error|caused" dev/side.log | head -3
