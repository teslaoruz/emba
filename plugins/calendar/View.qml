// The next couple of events today, from status.py (Emba polls it every minute).
import QtQuick

Column {
    id: cal

    property var app
    property var theme
    readonly property var events: (app?.pluginData?.calendar?.events ?? []).slice(0, 2)

    visible: events.length > 0
    width: parent ? parent.width : 300
    spacing: 4

    function when(iso) {
        const d = new Date(iso), mins = Math.round((d - Date.now()) / 60000);
        if (mins <= 0)
            return "now";
        if (mins < 60)
            return `in ${mins} min`;
        return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
    }

    Repeater {
        model: cal.events

        Rectangle {
            required property var modelData

            width: cal.width
            height: 32
            radius: 12
            color: cal.theme.fill

            Text {
                x: 12
                width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                text: `${modelData.title}  ·  ${cal.when(modelData.start)}${modelData.where ? "  ·  " + modelData.where : ""}`
                color: cal.theme.text
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
    }
}
