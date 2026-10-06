// Bluesky and Mastodon, from status.py (Emba polls it every two minutes).
import QtQuick

Column {
    id: social

    property var app
    property var theme
    readonly property var info: app?.pluginData?.social ?? {}
    readonly property var lines: {
        const out = [];
        const b = info.bluesky, m = info.mastodon;
        if (b?.error || (b?.unread ?? 0) > 0)
            out.push({ text: b.error ?? (b.latest?.length === 1 || b.unread === 1 ? `Bluesky: ${b.latest[0].who} ${b.latest[0].what}` : `Bluesky: ${b.unread} new`), error: !!b.error, url: "https://bsky.app/notifications" });
        if (m?.error || (m?.new ?? 0) > 0)
            out.push({ text: m.error ?? (m.new === 1 ? `Mastodon: ${m.latest[0].who} ${m.latest[0].what}` : `Mastodon: ${m.new} new`), error: !!m.error, url: "" });
        return out;
    }

    visible: lines.length > 0
    width: parent ? parent.width : 300
    spacing: 4

    Repeater {
        model: social.lines

        Rectangle {
            required property var modelData

            width: social.width
            height: 32
            radius: 12
            color: sh.hovered && modelData.url ? social.theme.fillHover : social.theme.fill

            Text {
                x: 12
                width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.text
                color: modelData.error ? social.theme.error : social.theme.text
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            HoverHandler { id: sh; cursorShape: modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { onTapped: if (modelData.url) Qt.openUrlExternally(modelData.url) }
        }
    }
}
