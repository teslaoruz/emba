#!/bin/sh
# CPU of Emba alone (no island) while it keeps moving: is it the drawing or the rest?
#   sh dev/cpu_panda.sh [MOOD]
cd "$(dirname "$0")/.."
cat > cpucheck.qml << EOF
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
PanelWindow {
    anchors.bottom: true; anchors.right: true
    WlrLayershell.layer: WlrLayer.Background
    implicitWidth: 120; implicitHeight: 120; color: "black"
    Panda { anchors.centerIn: parent; width: 72; height: 72; lively: false; mood: "${1:-working}" }
}
EOF
EMBA_SOCKET="$XDG_RUNTIME_DIR/emba-cpu2.sock" qs -p cpucheck.qml > /dev/null 2>&1 &
pid=$!
sleep 3
python3 dev/cpu.py $pid 6
kill $pid
rm cpucheck.qml
