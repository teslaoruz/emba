#!/bin/sh
# Record Emba's moves: sh dev/record_moves.sh -> docs/moves.gif
# Drawn on the background layer and grabbed from inside, so it never covers your windows.
cd "$(dirname "$0")/.."
frames=$PWD/dev/mframes
rm -rf $frames && mkdir -p $frames
EMBA_GRAB=$frames EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-preview.sock" qs -p moves.qml > dev/moves.log 2>&1 &  # its own socket: not "another Emba"
pid=$!
sleep 23
kill $pid
n=$(ls $frames | wc -l)
ffmpeg -loglevel error -y -framerate 20 -i $frames/%04d.png \
    -vf "fps=12,scale=260:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=80[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
    docs/moves.gif
echo "$n frames"; ls -la docs/moves.gif
