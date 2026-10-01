#!/bin/sh
# Record the README demo: a scripted little story, grabbed frame by frame.
#   sh dev/record.sh  ->  docs/demo.gif
# Runs a separate Emba on its own socket, so your real sessions stay out of it.
cd "$(dirname "$0")/.."
read -r W H X Y << EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height) \(.x) \(.y)"')
EOF
geo="$((X + W - 500)),$Y 500x230"
frames=dev/frames
rm -rf $frames && mkdir -p $frames
cursor() { hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1 || hyprctl dispatch movecursor "$1" "$2" > /dev/null; }

python3 bin/emba quit > /dev/null; sleep 0.5          # your real Emba
export EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-demo.sock"
emba() { python3 bin/emba "$@" > /dev/null; }
qs -p dev/backdrop.qml > /dev/null 2>&1 &
bd=$!
cursor $((X + W - 700)) $((Y + 500))
emba start
sleep 1.5

touch $frames/.go
( i=0; while [ -f $frames/.go ]; do grim -g "$geo" "$(printf "$frames/%04d.png" $i)"; i=$((i + 1)); sleep 0.03; done ) &
rec=$!

sleep 0.8
cursor $((X + W - 3)) $((Y + 3));          sleep 2.2   # the mouse finds the corner
cursor $((X + W - 700)) $((Y + 500));      sleep 1.2   # and leaves
python3 dev/fake.py start;                 sleep 2.0
emba toggle;                               sleep 2.2
python3 dev/fake.py ask > /dev/null &      sleep 2.4
emba allow;                                sleep 1.2
python3 dev/fake.py done;                  sleep 3.0
emba care;                                 sleep 0.6
emba feed;                                 sleep 1.8
emba toggle;                               sleep 1.0
rm $frames/.go
wait $rec
python3 dev/fake.py end
emba quit
kill $bd
unset EMBA_SOCKET
python3 bin/emba start > /dev/null

ffmpeg -loglevel error -y -framerate 14 -i $frames/%04d.png \
    -vf "fps=14,scale=500:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
    docs/demo.gif
ls -la docs/demo.gif
