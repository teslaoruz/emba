// One big Emba going through its moves, for recording: qs -p moves.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

PanelWindow {
    id: win

    anchors.bottom: true
    anchors.right: true
    margins.bottom: 20
    margins.right: 20
    exclusionMode: ExclusionMode.Ignore
    // behind every window: recording never covers what you are doing
    WlrLayershell.layer: WlrLayer.Background
    implicitWidth: 360
    implicitHeight: 300
    color: "#000000"

    property int i: 0
    readonly property var script: [
        ["idle", "wave"], ["idle", "dance"], ["working", ""], ["thinking", ""], ["idle", "hop"],
        ["idle", "spin"], ["waiting", ""], ["idle", "stretch"], ["idle", "sneeze"], ["done", ""], ["idle", "tailchase"]
    ]

    Rectangle {
        id: stage

        anchors.fill: parent
        color: "#000000"

        Panda {
            id: pd

            anchors.centerIn: parent
            width: 190
            height: 190
            lively: false
        }
    }
    Timer {
        running: true
        repeat: true
        interval: 1900
        triggeredOnStart: true
        onTriggered: {
            const [mood, move] = win.script[win.i % win.script.length];
            pd.mood = mood;
            if (move)
                pd.act(move);
            win.i++;
        }
    }

    // EMBA_GRAB=dir: save a frame every 50 ms, for dev/record_moves.sh
    property int frame: 0
    Timer {
        running: Quickshell.env("EMBA_GRAB") !== null
        interval: 50
        repeat: true
        onTriggered: stage.grabToImage(r => r.saveToFile(`${Quickshell.env("EMBA_GRAB")}/${String(win.frame++).padStart(4, "0")}.png`))
    }
}
