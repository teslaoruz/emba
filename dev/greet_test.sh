#!/bin/sh
# The hello on start, as it looks from a fresh, separate Emba.
#   sh dev/greet_test.sh -> dev/greet.png
cd "$(dirname "$0")/.."
T=$(mktemp -d); mkdir -p "$T/emba"; echo '{}' > "$T/emba/config.json"
export XDG_CONFIG_HOME=$T EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-greet.sock"
qs -p . > dev/greet.log 2>&1 &
pid=$!
sleep 3.6; python3 bin/emba snapshot "$PWD/dev/g1.png"; sleep 0.6
sleep 4.5; python3 bin/emba snapshot "$PWD/dev/g2.png"; sleep 0.6
kill $pid
python3 dev/readme_views.py dev/greet.png dev/g1.png
