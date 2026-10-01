#!/bin/sh
# Record the README demo: a scripted little story, grabbed frame by frame.
#   sh dev/record.sh  ->  docs/demo.gif
cd "$(dirname "$0")/.."
geo=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.x + .width - 500),\(.y) 500x220"')
frames=dev/frames
rm -rf $frames && mkdir -p $frames
emba() { python3 bin/emba "$@" > /dev/null; }

python3 bin/emba quit > /dev/null; sleep 0.5
qs -p dev/backdrop.qml > /dev/null 2>&1 &
bd=$!
python3 bin/emba start > /dev/null
python3 dev/fake.py end 2> /dev/null
sleep 1

# grab ~12 frames a second in the background
touch $frames/.go
( i=0; while [ -f $frames/.go ]; do grim -g "$geo" "$(printf "$frames/%04d.png" $i)"; i=$((i + 1)); sleep 0.04; done ) &
rec=$!

sleep 1.2
python3 dev/fake.py start;                 sleep 2.2
emba toggle;                               sleep 2.4
python3 dev/fake.py ask > /dev/null &      sleep 2.6
emba allow;                                sleep 1.2
python3 dev/fake.py done;                  sleep 3.2
emba care;                                 sleep 0.8
emba play;                                 sleep 3.0
emba toggle;                               sleep 1.2
rm $frames/.go
wait $rec
python3 dev/fake.py end
kill $bd

ffmpeg -loglevel error -y -framerate 12 -i $frames/%04d.png \
    -vf "fps=12,scale=500:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
    docs/demo.gif
ls -la docs/demo.gif
