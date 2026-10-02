// A QML plugin is any Item. Emba sets `app` (sessions, limits, ask(), ...)
// and `theme` (colours) on it and shows it in the island's overview.
import QtQuick

Text {
    property var app
    property var theme
    property int tick

    // under a minute says nothing worth a line
    readonly property var running: (tick, (app?.sessions ?? []).filter(s => s.started && Date.now() - s.started >= 60000))

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
        running: (parent.app?.sessions ?? []).length > 0
        interval: 30000
        repeat: true
        onTriggered: parent.tick++
    }
}
