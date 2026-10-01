// Contact sheet of Emba's moods and emotes: qs -p preview.qml
import QtQuick
import Quickshell

// A layer-shell panel rather than a window so the compositor never tiles it:
// dev/shot.sh grabs it at a fixed spot in the bottom-right corner.
PanelWindow {
    anchors.bottom: true
    anchors.right: true
    margins.bottom: 20
    margins.right: 20
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 960
    implicitHeight: 340
    color: "#1b1d22"

    Grid {
        anchors.centerIn: parent
        columns: 5
        spacing: 14

        Repeater {
            model: ["idle", "working", "waiting", "done", "error", "sleeping", "limit", "thinking", "love", "dizzy"]

            Column {
                required property string modelData

                Panda {
                    width: 130
                    height: 130
                    mood: ["love", "dizzy"].includes(modelData) ? "idle" : modelData
                    Component.onCompleted: if (["love", "dizzy"].includes(modelData))
                        emote(modelData, 999)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData
                    color: "#8a8f98"
                    font.pixelSize: 11
                }
            }
        }
    }
}
