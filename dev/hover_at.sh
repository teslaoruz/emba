#!/bin/sh
# Hover a point and grab a region:  sh dev/hover_at.sh X Y OUT [GEOM]
cd "$(dirname "$0")/.."
hyprctl dispatch "hl.dsp.cursor.move({x=$1,y=$2})" > /dev/null 2>&1
ydotool mousemove -x 1 -y 0 > /dev/null; sleep 0.1; ydotool mousemove -x -1 -y 0 > /dev/null
sleep 0.6
grim -g "${4:-1420,0 500x200}" "$3"
