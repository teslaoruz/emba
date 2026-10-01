// Emba on Windows, macOS and Linux desktops without layer-shell: the same
// Island and Settings as shell.qml, in ordinary frameless Qt windows.
import QtQuick
import QtQuick.Window
import Quickshell
import qs

Window {
    id: win

    readonly property string pos: App.cfg.position ?? "top-right"
    readonly property int v: pos.startsWith("top") ? 0 : pos.startsWith("bottom") ? 2 : 1
    readonly property int h: pos.endsWith("left") ? 0 : pos.endsWith("right") ? 2 : 1
    readonly property real s: App.cfg.scale ?? 1
    readonly property var scr: Qt.application.screens.find(x => x.name === App.cfg.screen) ?? Qt.application.screens[0]
    // the work area, so the island never hides under a taskbar or menu bar
    readonly property var area: Quickshell.availableGeometry(scr.name)

    screen: scr
    width: 480 * s
    height: 380 * s
    x: area.x + (h === 0 ? App.cfg.marginX : h === 2 ? area.width - width - App.cfg.marginX : (area.width - width) / 2)
    y: area.y + (v === 0 ? App.cfg.marginY : v === 2 ? area.height - height - App.cfg.marginY : (area.height - height) / 2)
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.NoDropShadowWindowHint
    color: "transparent"
    visible: true
    title: "Emba"

    Island {
        id: island

        anchors.fill: parent
        hAlign: win.h / 2
        vAlign: win.v / 2
        s: win.s
        origin: Qt.point(win.x, win.y)
    }

    // Only the island takes clicks; the rest of the window passes them through.
    function updateMask() {
        const r = island.shape.mapToItem(null, 0, 0, island.shape.width, island.shape.height);
        Quickshell.setMask(win, Math.floor(r.x), Math.floor(r.y), Math.ceil(r.width), Math.ceil(r.height));
    }
    Connections {
        target: island.shape

        function onXChanged() { win.updateMask(); }
        function onYChanged() { win.updateMask(); }
        function onWidthChanged() { win.updateMask(); }
        function onHeightChanged() { win.updateMask(); }
    }
    Component.onCompleted: updateMask()

    // the ask box should take typing straight away, as on Linux
    Connections {
        target: island

        function onViewChanged() {
            if (island.open && island.view === "ask")
                win.requestActivate();
        }
    }

    Window {
        title: "Emba"
        width: 460
        height: 680
        visible: App.settingsOpen
        color: Theme.base
        onClosing: App.settingsOpen = false

        Settings {
            anchors.fill: parent
        }
    }
}
