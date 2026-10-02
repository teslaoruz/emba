#!/bin/sh
# A separate Emba: sessions idle (dots), then busy (breathing dots in the pill).
#   sh dev/dots_test.sh -> dev/dots.png
cd "$(dirname "$0")/.."
T=$(mktemp -d); mkdir -p "$T/emba"; echo '{}' > "$T/emba/config.json"
export XDG_CONFIG_HOME=$T EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-dots.sock"
qs -p . > dev/dots.log 2>&1 &
pid=$!
sleep 3
python3 dev/fake.py many; python3 dev/fake.py finish
sleep 37
python3 bin/emba snapshot "$PWD/dev/d-idle.png"; sleep 0.6
python3 dev/fake.py many; sleep 1.5
rm -rf dev/bt; mkdir dev/bt
python3 bin/emba snapshot "$PWD/dev/bt/%d.png"; sleep 1.6
kill $pid
python3 dev/readme_views.py dev/dots.png dev/d-idle.png dev/bt/00.png dev/bt/04.png dev/bt/08.png
