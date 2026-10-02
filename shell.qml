// emba: a little red panda that sits on the edge of your screen and keeps an
// eye on your Claude Code sessions.  Run with: qs -p /path/to/emba
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs

ShellRoot {
    // music for Emba to dance to
    Binding {
        target: App
        property: "music"
        value: {
            const p = Mpris.players.values.find(x => x.isPlaying);
            return p ? (p.trackTitle || p.identity || "music") : "";
        }
    }

    PanelWindow {
        id: win

        // "top-right" -> v 0, h 2; "left" -> v 1, h 0; "bottom" -> v 2, h 1
        readonly property string pos: App.cfg.position ?? "top-right"
        readonly property int v: pos.startsWith("top") ? 0 : pos.startsWith("bottom") ? 2 : 1
        readonly property int h: pos.endsWith("left") ? 0 : pos.endsWith("right") ? 2 : 1
        readonly property real s: App.cfg.scale ?? 1

        screen: Quickshell.screens.find(x => x.name === App.cfg.screen) ?? Quickshell.screens[0]

        anchors.top: v === 0
        anchors.bottom: v === 2
        anchors.left: h === 0
        anchors.right: h === 2
        margins.top: App.cfg.marginY
        margins.bottom: App.cfg.marginY
        margins.left: App.cfg.marginX
        margins.right: App.cfg.marginX

        // Room for the biggest view; everything outside the island itself
        // is cut out of the input region, so clicks go straight through.
        implicitWidth: 480 * s
        implicitHeight: 380 * s
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "emba"
        // The ask box takes the keyboard (you asked to type); everything else,
        // approvals above all, only gets keys after you click it.
        // and while open, a click on the island gives it the keyboard like any window
        WlrLayershell.keyboardFocus: island.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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
    // Click anywhere else and the island closes, like a menu. Only when you
    // opened it yourself, and never over a permission request.
    HyprlandFocusGrab {
        windows: [win]
        active: island.open && island.userOpened && island.view !== "approval"
        onCleared: island.collapse()
    }


    LazyLoader {
        active: App.settingsOpen

        FloatingWindow {
            title: "Emba"
            implicitWidth: 460
            implicitHeight: 680
            visible: true
            onVisibleChanged: if (!visible)
                App.settingsOpen = false

            Settings {
                anchors.fill: parent
            }
        }
    }
}
