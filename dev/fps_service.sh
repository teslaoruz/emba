#!/bin/sh
# Frames per second the running Emba draws while left alone (restarts the
# service with Qt's render timing on, counts frames for N seconds, restores).
#   sh dev/fps_service.sh [SECONDS]
systemctl --user set-environment QSG_RENDER_TIMING=1
systemctl --user restart emba
sleep 25
since=$(date +%s)
sleep "${1:-5}"
systemctl --user unset-environment QSG_RENDER_TIMING
n=$(journalctl --user -u emba --since "@$since" -o cat | grep -c "frame rendered")
echo "frames in ${1:-5}s: $n"
systemctl --user restart emba
