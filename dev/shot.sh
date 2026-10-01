#!/bin/sh
# Compile the shader, show a preview QML for a moment, screenshot it.
# usage: dev/shot.sh [preview.qml] [out.png] [WxH]
set -eu
cd "$(dirname "$0")/.."
qml=${1:-preview.qml}
out=${2:-dev/shot.png}
size=${3:-960x340}
w=${size%x*}; h=${size#*x}
mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.x) \(.y) \(.width) \(.height)"')
set -- $mon
EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-preview.sock" qs -p "$qml" > dev/qs.log 2>&1 &
pid=$!
sleep ${SHOT_WAIT:-2.5}
grim -g "$(($1 + $3 - w - 20)),$(($2 + $4 - h - 20)) ${w}x${h}" "$out"
kill $pid 2>/dev/null || true
grep -iE "error|warn" dev/qs.log | grep -v "QSettings" | head -20 || true
echo "$out"
