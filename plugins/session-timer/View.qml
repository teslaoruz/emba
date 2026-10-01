// A QML plugin is any Item. Emba sets `app` (sessions, limits, ask(), ...)
// and `theme` (colours) on it and shows it in the island's overview.
import QtQuick

Text {
    property var app
    property var theme
    property int tick

    readonly property var running: (app?.sessions ?? []).filter(s => s.started)

    function ago(ms) {
        const m = Math.floor(ms / 60000);
        return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${m % 60}m`;
    }

    visible: running.length > 0
    text: (tick, running.map(s => `${s.name} ${ago(Date.now() - s.started)}`).join("  ·  "))
    color: theme?.dim ?? "gray"
    font.pixelSize: 11
    elide: Text.ElideRight

    Timer {
        running: parent.visible
        interval: 30000
        repeat: true
        onTriggered: parent.tick++
    }
}
