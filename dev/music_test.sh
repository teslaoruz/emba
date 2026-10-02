#!/bin/sh
# A separate Emba (own socket, default settings) with a fake player "playing".
#   sh dev/music_test.sh
cd "$(dirname "$0")/.."
python3 bin/emba quit > /dev/null 2>&1
T=$(mktemp -d); mkdir -p "$T/emba"; echo '{}' > "$T/emba/config.json"
XDG_CONFIG_HOME=$T EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-music.sock" qs -p . > dev/music.log 2>&1 &
pid=$!
sleep 3; grim -g "1420,0 500x200" dev/m-0-silent.png
python3 -W ignore dev/fake_mpris.py 8 &
sleep 2.5; grim -g "1420,0 500x200" dev/m-1-music.png
sleep 0.35; grim -g "1420,0 500x200" dev/m-2-music.png
sleep 0.35; grim -g "1420,0 500x200" dev/m-3-music.png
printf 'cpu while dancing: '; python3 dev/cpu.py $pid 4
sleep 5; grim -g "1420,0 500x200" dev/m-4-stopped.png
kill $pid
python3 dev/sheet.py dev/music.png dev/m-0-silent.png dev/m-1-music.png dev/m-2-music.png dev/m-3-music.png dev/m-4-stopped.png
