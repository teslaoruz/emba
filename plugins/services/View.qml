// Your services: one line from each that has a key (Settings → Integrations):
// Vercel deployments, Stripe payments today, Resend emails, the next Cal.com
// booking, the latest Notion page, failed n8n runs. Click a line to open it.
import QtQuick
import Quickshell.Io

Column {
    id: svc

    property var app
    property var theme
    property var lines: []
    property var incoming: []

    readonly property string script: Qt.resolvedUrl("status.py").toString().replace(/^file:\/\//, "").replace(/^\/([A-Za-z]:)/, "$1")

    visible: lines.length > 0
    width: parent ? parent.width : 300
    spacing: 4

    function refresh() {
        if (proc.running || !app)
            return;
        incoming = [];
        proc.command = [app.status?.python || app.python, script];
        proc.running = true;
    }
    // the last answer shows at once (the island rebuilds this panel each time it opens)
    onAppChanged: {
        if (app?.pluginData?.services)
            lines = app.pluginData.services;
        refresh();
    }

    Timer {
        running: !!svc.app
        interval: 120000
        repeat: true
        onTriggered: svc.refresh()
    }

    Process {
        id: proc

        stdout: SplitParser {
            onRead: line => {
                try {
                    svc.incoming = svc.incoming.concat([JSON.parse(line)]);
                } catch (e) {}
            }
        }
        onExited: {
            svc.lines = svc.incoming;
            if (svc.app)
                svc.app.pluginData = Object.assign({}, svc.app.pluginData, {
                    services: svc.lines
                });
        }
    }

    Repeater {
        model: svc.lines

        Rectangle {
            id: row

            required property var modelData

            width: svc.width
            height: 40
            radius: 12
            color: rh.hovered && row.modelData.url ? svc.theme.fillHover : svc.theme.fill

            Rectangle {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: ({ ok: "#3ecf8e", bad: "#ff453a", busy: "#f5b14c", warn: "#f5b14c" })[row.modelData.state] ?? svc.theme.faint
            }
            Column {
                x: 28
                width: parent.width - 40
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: row.modelData.title ?? ""
                    color: svc.theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    width: parent.width
                    text: row.modelData.detail ?? ""
                    color: svc.theme.dim
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
            HoverHandler { id: rh; cursorShape: row.modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { onTapped: if (/^https:\/\//.test(row.modelData.url ?? "")) Qt.openUrlExternally(row.modelData.url) }
        }
    }
}
