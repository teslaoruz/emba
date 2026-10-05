#!/bin/sh
# Open and close the running Emba from the command line (no mouse) while six
# grim loops grab the corner (about 40 fps together, each frame named by when
# it was taken), then print where the island's edges were in each frame: a
# smooth animation moves steadily, a jump shows as a step back or an edge
# leaving the side of the screen.
#   sh dev/openclose.sh [ROUNDS]     -> dev/oc/*.png and a table
cd "$(dirname "$0")/.."
read -r W X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.x) \(.y)"')
EOF
R=$((X + W))
out=$PWD/dev/oc; rm -rf "$out"; mkdir -p "$out"
python3 bin/emba close > /dev/null; sleep 1.2
touch "$out/.go"
k=0; while [ $k -lt 6 ]; do
    (while [ -e "$out/.go" ]; do grim -g "$((R - 520)),$Y 520x480" "$out/$(date +%s%N).png"; done) &
    k=$((k + 1))
done
sleep 0.5
i=0; while [ $i -lt "${1:-2}" ]; do
    python3 bin/emba open > /dev/null; sleep 1.2
    python3 bin/emba close > /dev/null; sleep 1.2
    i=$((i + 1))
done
rm -f "$out/.go"; sleep 0.5
.venv/bin/python dev/edges.py "$out"
