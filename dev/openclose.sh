#!/bin/sh
# Open and close the running Emba from the command line (no mouse) while the
# corner is recorded at 60 fps, then print where the island's edges were in
# each frame: a smooth animation moves steadily, a jump shows as a step back
# or an edge leaving the screen side.
#   sh dev/openclose.sh [ROUNDS]     -> dev/oc/*.png and a table
cd "$(dirname "$0")/.."
read -r W X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.x) \(.y)"')
EOF
R=$((X + W))
out=$PWD/dev/oc; rm -rf "$out"; mkdir -p "$out"
python3 bin/emba close > /dev/null; sleep 1.2
gpu-screen-recorder -w region -region "520x480+$((R - 520))+$Y" -f 60 -o "$out/rec.mp4" > "$out/rec.log" 2>&1 & G=$!
sleep 1
i=0; while [ $i -lt "${1:-2}" ]; do
    python3 bin/emba open > /dev/null; sleep 1.2
    python3 bin/emba close > /dev/null; sleep 1.2
    i=$((i + 1))
done
kill -INT $G; wait $G
ffmpeg -loglevel error -i "$out/rec.mp4" "$out/%04d.png"
.venv/bin/python dev/edges.py "$out"
