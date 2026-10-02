#!/bin/sh
# Shake the real cursor (no clicks) and see whether Emba starts listening.
#   sh dev/shake_test.sh [SWINGS] [PAUSE]
cd "$(dirname "$0")/.."
n=${1:-8} pause=${2:-0.09}
to() { hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1; }
i=0
while [ $i -lt $n ]; do
    to 800 500; sleep "$pause"; to 1000 500; sleep "$pause"
    i=$((i + 1))
done
sleep 0.8
if pgrep -f "voice.py listen" > /dev/null; then echo "listening: yes"; pkill -f "voice.py listen"; else echo "listening: no"; fi
