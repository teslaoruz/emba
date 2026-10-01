// Plain backdrop under the island's corner, so README screenshots show emba
// and not whatever is on the desktop: qs -p dev/backdrop.qml
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    anchors.top: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    implicitWidth: 500
    implicitHeight: 400
    color: "#2a2f3a"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#3a3f5c" }
            GradientStop { position: 1; color: "#1f2230" }
        }
    }
}
