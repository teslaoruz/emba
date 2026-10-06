// Unread mail, from status.py (Emba polls it every two minutes).
import QtQuick

Rectangle {
    id: mail

    property var app
    property var theme
    readonly property var info: app?.pluginData?.mail ?? {}

    visible: !!info.error || (info.unread ?? 0) > 0
    width: parent ? parent.width : 300
    height: 32
    radius: 12
    color: theme.fill

    Text {
        x: 12
        width: parent.width - 24
        anchors.verticalCenter: parent.verticalCenter
        text: mail.info.error ? mail.info.error
            : mail.info.unread === 1 && mail.info.latest?.length ? `Unread: ${mail.info.latest[0].from} · ${mail.info.latest[0].subject}`
            : `${mail.info.unread} unread emails${mail.info.latest?.length ? "  ·  latest from " + mail.info.latest[0].from : ""}`
        color: mail.info.error ? mail.theme.error : mail.theme.text
        font.pixelSize: 12
        elide: Text.ElideRight
    }
}
