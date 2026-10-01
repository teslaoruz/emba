// One big Emba going through its moves, for recording: qs -p moves.qml
import QtQuick
import Quickshell
import qs

PanelWindow {
    id: win

    anchors.bottom: true
    anchors.right: true
    margins.bottom: 20
    margins.right: 20
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 360
    implicitHeight: 300
    color: "#262a36"

    property int i: 0
    readonly property var script: [
        ["idle", "wave"], ["idle", "dance"], ["working", ""], ["thinking", ""], ["idle", "hop"],
        ["idle", "spin"], ["waiting", ""], ["idle", "stretch"], ["idle", "sneeze"], ["done", ""], ["idle", "tailchase"]
    ]

    Panda {
        id: pd

        anchors.centerIn: parent
        width: 190
        height: 190
        lively: false
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
}
