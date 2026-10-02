// Contact sheet of Emba's moods and moves: qs -p preview.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// A layer-shell panel rather than a window so the compositor never tiles it:
// dev/shot.sh grabs it at a fixed spot in the bottom-right corner.
PanelWindow {
    anchors.bottom: true
    anchors.right: true
    margins.bottom: 20
    margins.right: 20
    exclusionMode: ExclusionMode.Ignore
    // behind every window: recording never covers what you are doing
    WlrLayershell.layer: WlrLayer.Background
    implicitWidth: 960
    implicitHeight: 340
    color: "#000000"

    Grid {
        id: grid

        anchors.centerIn: parent
        columns: 5
        spacing: 14

        Repeater {
            model: [
                { label: "idle", mood: "idle" },
                { label: "working", mood: "working" },
                { label: "thinking", mood: "thinking" },
                { label: "listening", mood: "listening" },
                { label: "needs you", mood: "waiting" },
                { label: "done", mood: "done" },
                { label: "dancing", mood: "idle", act: "dance" },
                { label: "stretching", mood: "idle", act: "stretch" },
                { label: "sleepy", mood: "sleepy" },
                { label: "petted", mood: "idle", emote: "love" }
            ]

            Column {
                required property var modelData

                Panda {
                    id: pd

                    width: 130
                    height: 130
                    mood: modelData.mood
                    lively: false

                    // keep the move going so a still frame can catch it
                    Timer {
                        running: !!modelData.act || !!modelData.emote
                        interval: modelData.act === "stretch" ? 2100 : 2500
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: modelData.act ? pd.act(modelData.act) : pd.emote(modelData.emote, 999)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label
                    color: "#9a9a9f"
                    font.pixelSize: 11
                }
            }
        }
    }

    // EMBA_GRAB=file.png: save one picture and stay put (the caller ends us)
    Timer {
        running: Quickshell.env("EMBA_GRAB") !== null
        interval: 2600
        onTriggered: grid.grabToImage(r => r.saveToFile(Quickshell.env("EMBA_GRAB")))
    }
}
