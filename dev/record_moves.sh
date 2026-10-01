#!/bin/sh
# Record Emba's moves: sh dev/record_moves.sh -> docs/moves.gif
cd "$(dirname "$0")/.."
read -r W H X Y << EOF2
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height) \(.x) \(.y)"')
EOF2
geo="$((X + W - 380)),$((Y + H - 320)) 360x300"
frames=dev/mframes
rm -rf $frames && mkdir -p $frames
EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-preview.sock" qs -p moves.qml > dev/moves.log 2>&1 &  # its own socket: not "another Emba"
pid=$!
sleep 2
touch $frames/.go
( i=0; while [ -f $frames/.go ]; do grim -g "$geo" "$(printf "$frames/%04d.png" $i)"; i=$((i + 1)); sleep 0.02; done ) &
rec=$!
sleep 21
rm $frames/.go
wait $rec
kill $pid
n=$(ls $frames | wc -l)
ffmpeg -loglevel error -y -framerate $((n / 21)) -i $frames/%04d.png \
    -vf "scale=300:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=80[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
    docs/moves.gif
echo "$n frames"; ls -la docs/moves.gif
