// perch: a little red panda that sits on the edge of your screen and keeps an
// eye on your Claude Code sessions.  Run with: qs -p /path/to/perch
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

ShellRoot {
    PanelWindow {
        id: win

        // "top-right" -> v 0, h 2; "left" -> v 1, h 0; "bottom" -> v 2, h 1
        readonly property string pos: Perch.cfg.position ?? "top-right"
        readonly property int v: pos.startsWith("top") ? 0 : pos.startsWith("bottom") ? 2 : 1
        readonly property int h: pos.endsWith("left") ? 0 : pos.endsWith("right") ? 2 : 1
        readonly property real s: Perch.cfg.scale ?? 1

        screen: Quickshell.screens.find(x => x.name === Perch.cfg.screen) ?? Quickshell.screens[0]

        anchors.top: v === 0
        anchors.bottom: v === 2
        anchors.left: h === 0
        anchors.right: h === 2
        margins.top: Perch.cfg.marginY
        margins.bottom: Perch.cfg.marginY
        margins.left: Perch.cfg.marginX
        margins.right: Perch.cfg.marginX

        // Room for the biggest view; everything outside the island itself
        // is cut out of the input region, so clicks go straight through.
        implicitWidth: 480 * s
        implicitHeight: 380 * s
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "perch"
        WlrLayershell.keyboardFocus: island.wantsKeys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        mask: Region {
            item: island.shape
        }

        // where this window sits on the screen, for global cursor tracking
        readonly property point origin: Qt.point(
            screen.x + (h === 0 ? margins.left : h === 2 ? screen.width - width - margins.right : (screen.width - width) / 2),
            screen.y + (v === 0 ? margins.top : v === 2 ? screen.height - height - margins.bottom : (screen.height - height) / 2))

        Island {
            id: island

            anchors.fill: parent
            hAlign: win.h / 2
            vAlign: win.v / 2
            s: win.s
            origin: win.origin
        }
    }
}
