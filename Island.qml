pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// The island: a dark rounded shape that grows out of its corner of the screen.
//
//   hidden    a small nub; nothing is running
//   peek      cursor touched the nub: Maple pops out and waves
//   compact   a pill while sessions run: Maple, the latest action, a dot per session
//   expanded  a card with one of the views below
//
// Laid out in unscaled units inside `stage`, which is scaled by `s`.
Item {
    id: root

    property real hAlign: 1
    property real vAlign: 0
    property real s: 1
    property point origin

    readonly property alias shape: shape
    readonly property bool wantsKeys: open && ["ask", "approval", "result", "file"].includes(view)

    // ---- state machine ----
    property bool open: false
    property bool peeking: false
    property string forcedView: ""      // finished | limit | ask | result | file
    property string finishedSid: ""
    property var files: []
    property bool dragging: false

    readonly property var sessions: Perch.sessions
    readonly property var pending: Perch.pending
    readonly property var focusSession: sessions[0]

    readonly property string mode: open ? "expanded" : peeking ? "peek" : (sessions.length || dragging || !Perch.cfg.hideWhenIdle) ? "compact" : "hidden"
    readonly property string view: {
        if (dragging)
            return "drop";
        if (pending.length && forcedView !== "ask")
            return "approval";
        if (forcedView)
            return forcedView;
        return sessions.length ? "overview" : "empty";
    }
    // views that stay open after the cursor leaves
    readonly property bool sticky: ["approval", "ask", "result", "file", "drop"].includes(view) || Perch.asking

    function expand(v) {
        forcedView = v ?? "";
        open = true;
        peeking = false;
        leaveTimer.stop();
    }
    function collapse() {
        open = false;
        forcedView = "";
        files = [];
    }

    Connections {
        target: Perch

        function onPermissionAsked() {
            maple.surprise();
            if (Perch.cfg.autoOpenOnPermission)
                root.expand(root.forcedView === "ask" ? "ask" : "");
        }
        function onFinished(sid) {
            if (!Perch.cfg.celebrate || (root.open && root.view !== "overview"))
                return;
            root.finishedSid = sid;
            root.expand("finished");
            if (!hover.hovered)
                autoClose.restart();
        }
        function onLimitWarning(window, percent) {
            maple.emote("surprised", 1);
            if (!root.open || root.view === "overview") {
                root.expand("limit");
                autoClose.restart();
            }
        }
        function onToggleRequested() {
            root.open ? root.collapse() : root.expand();
        }
        function onAskRequested() {
            root.expand("ask");
        }
    }

    Timer {
        id: autoClose

        interval: 5200
        onTriggered: if (!hover.hovered && !root.pending.length)
            root.collapse()
    }
    Timer {
        id: openTimer

        onTriggered: root.expand()
    }
    Timer {
        id: unpeek

        interval: 600
        onTriggered: root.peeking = false
    }
    Timer {
        id: leaveTimer

        interval: Perch.cfg.collapseDelay ?? 1200
        onTriggered: if (!root.sticky)
            root.collapse()
    }

    // ---- mood: what Maple shows ----
    readonly property string mood: {
        if (dragging)
            return "idle";
        if (pending.length)
            return "waiting";
        if (Perch.asking)
            return "thinking";
        if (open && view === "finished")
            return "done";
        if (open && view === "limit")
            return "limit";
        const s = focusSession;
        if (!s)
            return Date.now() - Perch.lastActivity > 600000 && mode !== "hidden" ? "sleeping" : "idle";
        if (s.state === "idle" && Math.max(Perch.limits.five_hour?.used ?? 0, Perch.limits.seven_day?.used ?? 0) >= Perch.cfg.limitWarn)
            return "limit";
        return {
            thinking: "thinking",
            working: "working",
            done: "done",
            waiting: "waiting"
        }[s.state] ?? "idle";
    }

    // ---- geometry per mode, unscaled ----
    readonly property size target: {
        if (mode === "hidden")
            return Qt.size(46, 10);
        if (mode === "peek")
            return Qt.size(76, 70);
        if (mode === "compact")
            return Qt.size(Math.min(300, 58 + compactLabel.implicitWidth + 14 + Math.min(sessions.length, 6) * 10 + 8), 44);
        return Qt.size(460, Math.max(132, Math.min(360, (content.item?.implicitHeight ?? 100) + 30)));
    }
    readonly property bool opening: mode === "expanded" || mode === "peek"

    Item {
        id: stage

        width: root.width / root.s
        height: root.height / root.s
        scale: root.s
        transformOrigin: Item.TopLeft

        Rectangle {
            id: shape

            width: root.target.width
            height: root.target.height
            x: (stage.width - width) * root.hAlign
            y: (stage.height - height) * root.vAlign
            radius: root.mode === "expanded" ? 26 : Math.min(height / 2, 24)
            color: Qt.rgba(0.05, 0.05, 0.06, root.mode === "hidden" ? 0.75 : 0.96)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, root.mode === "hidden" ? 0.12 : 0.07)
            clip: true

            Behavior on width { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic; easing.overshoot: 1.1 } }
            Behavior on height { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic; easing.overshoot: 1.1 } }
            Behavior on radius { NumberAnimation { duration: 340 } }
            Behavior on color { ColorAnimation { duration: 340 } }

            // a pulse around the edge while something waits on you
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 2
                border.color: "#f5a524"
                opacity: root.pending.length && root.mode !== "expanded" ? pulse.value : 0

                QtObject {
                    id: pulse

                    property real value: 0.3

                    SequentialAnimation on value {
                        running: root.pending.length > 0
                        loops: Animation.Infinite
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
            }

            HoverHandler {
                id: hover

                onHoveredChanged: {
                    if (hovered) {
                        leaveTimer.stop();
                        unpeek.stop();
                        autoClose.stop();
                        if (root.mode === "hidden") {
                            root.peeking = true;
                            maple.wave();
                            openTimer.interval = 650;
                            openTimer.restart();
                        } else if (root.mode === "compact") {
                            openTimer.interval = 260;
                            openTimer.restart();
                        }
                    } else {
                        openTimer.stop();
                        if (root.peeking && !root.open)
                            unpeek.restart();
                        else if (root.open)
                            leaveTimer.restart();
                    }
                }
            }

            TapHandler {
                onTapped: if (!root.open)
                    root.expand()
            }

            // files dragged in from a file manager
            DropArea {
                anchors.fill: parent
                onEntered: drag => {
                    root.dragging = true;
                    maple.emote("surprised", 30);
                }
                onExited: {
                    root.dragging = false;
                    maple.emote("", 0);
                }
                onDropped: drop => {
                    root.dragging = false;
                    const paths = drop.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter(p => p.startsWith("/"));
                    if (!paths.length)
                        return;
                    root.files = paths;
                    maple.gulp();
                    root.expand("file");
                }
            }

            // ---- Maple, one instance travelling between modes ----
            Maple {
                id: maple

                property real px: root.mode === "expanded" ? 96 : root.mode === "peek" ? 70 : root.mode === "compact" ? 46 : 20

                width: px
                height: px
                x: root.mode === "expanded" ? 12 : root.mode === "compact" ? 2 : (shape.width - px) / 2
                y: root.mode === "expanded" ? Math.min(18, (shape.height - px) / 2) : (shape.height - px) / 2 + (root.mode === "compact" ? 1 : 0)
                opacity: root.mode === "hidden" ? 0 : 1
                running: root.mode !== "hidden"
                mood: root.mood
                bodyColor: Perch.cfg.color

                Behavior on px { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic } }
                Behavior on x { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic } }
                Behavior on y { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }

                gaze: hover.hovered ? Qt.point(hover.point.position.x - x - width / 2, hover.point.position.y - y - height / 2) : cursor.gaze

                onClicked: root.open ? boop() : root.expand()
            }

            // ---- compact: the latest action and a dot per session ----
            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 54
                spacing: 8
                opacity: root.mode === "compact" ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: root.mode === "compact" ? 260 : 120 } }

                Text {
                    id: compactLabel

                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 190)
                    elide: Text.ElideRight
                    text: root.pending.length ? `${root.pending[0].name} needs you` : root.dragging ? "Drop it on Maple" : root.focusSession ? (root.focusSession.ticker.slice(-1)[0] ?? root.focusSession.name) : ""
                    color: root.pending.length ? "#f5a524" : "#e8e9ec"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: root.sessions.slice(0, 6)

                        Rectangle {
                            required property var modelData

                            width: 6
                            height: 6
                            radius: 3
                            color: Perch.stateColours[modelData.state] ?? "#8b9099"
                        }
                    }
                }
            }

            // ---- expanded views ----
            Loader {
                id: content

                x: 116
                y: 16
                width: shape.width - 132
                active: root.mode === "expanded"
                opacity: root.mode === "expanded" ? 1 : 0
                sourceComponent: ({
                        overview: overviewView,
                        empty: emptyView,
                        approval: approvalView,
                        finished: finishedView,
                        limit: limitView,
                        ask: askView,
                        result: resultView,
                        file: fileView,
                        drop: dropView
                    })[Perch.asking && root.view === "ask" ? "result" : root.view] ?? emptyView

                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation { duration: root.mode === "expanded" ? 160 : 0 }
                        NumberAnimation { duration: root.mode === "expanded" ? 300 : 120 }
                    }
                }
            }

            // close button in the corner of every view
            Text {
                visible: root.mode === "expanded" && root.view !== "approval"
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                text: "✕"
                color: closeHover.hovered ? "#e8e9ec" : "#5f646d"
                font.pixelSize: 12

                HoverHandler { id: closeHover }
                TapHandler { onTapped: root.collapse() }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.collapse();
                } else if (root.view === "approval" && root.pending.length) {
                    if (event.key === Qt.Key_Y)
                        root.decide("allow");
                    else if (event.key === Qt.Key_N)
                        root.decide("deny");
                }
            }
            focus: root.wantsKeys
        }
    }

    function decide(behavior, always) {
        const req = pending[0];
        if (!req)
            return;
        Perch.decide(req.id, behavior, always);
        if (behavior === "allow")
            maple.emote("happy", 1);
        else
            maple.emote("annoyed", 0.8);
        if (pending.length === 0 && !hover.hovered)
            leaveTimer.restart();
    }

    // ---- the cursor, anywhere on screen (Hyprland only) ----
    QtObject {
        id: cursor

        property var gaze: null
    }

    Process {
        running: (Perch.cfg.trackCursor ?? true) && root.mode !== "hidden" && !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
        command: ["sh", "-c", "while hyprctl cursorpos; do sleep 0.08; done"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/(-?\d+),\s*(-?\d+)/);
                if (!m)
                    return;
                const c = maple.mapToItem(null, maple.width / 2, maple.height / 2);
                cursor.gaze = Qt.point(+m[1] - root.origin.x - c.x * root.s, +m[2] - root.origin.y - c.y * root.s);
            }
        }
        onRunningChanged: if (!running)
            cursor.gaze = null
    }

    // ================================================================ views

    component Label: Text {
        color: "#e8e9ec"
        font.pixelSize: 13
        wrapMode: Text.Wrap
    }

    component Dim: Text {
        color: "#8b9099"
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    component Pill: Rectangle {
        id: pill

        property string text
        property string key
        property bool primary
        signal clicked

        implicitWidth: row.implicitWidth + 24
        implicitHeight: 30
        radius: 15
        color: primary ? (ph.hovered ? "#ffffff" : "#f5f6f8") : Qt.rgba(1, 1, 1, ph.hovered ? 0.15 : 0.09)
        scale: tap.pressed ? 0.94 : 1

        Behavior on scale { NumberAnimation { duration: 90 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.primary ? "#0b0c0e" : "#e8e9ec"
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            Rectangle {
                visible: pill.key !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 4
                color: "transparent"
                border.width: 1
                border.color: pill.primary ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(1, 1, 1, 0.25)

                Text {
                    anchors.centerIn: parent
                    text: pill.key
                    color: pill.primary ? "#0b0c0e" : "#c0c4cc"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
        }

        HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: pill.clicked() }
    }

    component Header: RowLayout {
        property string title
        property string sub
        property color dot: "#8b9099"

        spacing: 6

        Rectangle {
            width: 7
            height: 7
            radius: 4
            color: parent.dot
        }
        Text {
            text: parent.title
            color: "#e8e9ec"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Dim {
            Layout.fillWidth: true
            text: parent.sub
        }
    }

    Component {
        id: overviewView

        ColumnLayout {
            spacing: 6

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: root.sessions.length === 1 ? "1 session" : `${root.sessions.length} sessions`
                sub: {
                    const l = Perch.limits;
                    const parts = [];
                    if (l.five_hour)
                        parts.push(`5h ${l.five_hour.used}%`);
                    if (l.seven_day)
                        parts.push(`7d ${l.seven_day.used}%`);
                    return parts.join(" · ");
                }
                dot: "#34d399"
            }

            Repeater {
                model: root.sessions.slice(0, 5)

                Rectangle {
                    id: srow

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 12
                    color: Qt.rgba(1, 1, 1, rh.hovered ? 0.08 : 0.04)

                    HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Perch.focus(srow.modelData.sid) }

                    Rectangle {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: Perch.stateColours[srow.modelData.state] ?? "#8b9099"

                        SequentialAnimation on opacity {
                            running: ["working", "thinking", "waiting"].includes(srow.modelData.state)
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 0.3; duration: 600 }
                            NumberAnimation { to: 1; duration: 600 }
                        }
                    }

                    Column {
                        x: 26
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 36

                        Text {
                            width: parent.width
                            text: srow.modelData.name
                            color: "#e8e9ec"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Dim {
                            width: parent.width
                            text: srow.modelData.ticker.slice(-1)[0] ?? srow.modelData.state
                            font.family: "monospace"
                            font.pixelSize: 11
                            opacity: srow.modelData.state === "working" ? shimmer.value : 1
                        }
                    }
                }
            }

            QtObject {
                id: shimmer

                property real value: 1

                SequentialAnimation on value {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
                }
            }

            Pill {
                text: "Ask Claude"
                onClicked: root.expand("ask")
            }
        }
    }

    Component {
        id: emptyView

        ColumnLayout {
            spacing: 10

            Label {
                Layout.fillWidth: true
                Layout.topMargin: 8
                text: "Nothing running right now."
                font.pixelSize: 14
            }
            Dim {
                text: "Start claude in a terminal, or ask here."
            }
            Pill {
                text: "Ask Claude"
                primary: true
                onClicked: root.expand("ask")
            }
        }
    }

    Component {
        id: approvalView

        ColumnLayout {
            readonly property var req: root.pending[0]

            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Header {
                    Layout.fillWidth: true
                    title: root.pending[0]?.name ?? ""
                    sub: root.pending.length > 1 ? `wants to use ${root.pending[0]?.tool} · 1 of ${root.pending.length}` : `wants to use ${root.pending[0]?.tool}`
                    dot: "#f5a524"
                }
                Dim {
                    text: "terminal ↗"
                    color: th.hovered ? "#e8e9ec" : "#8b9099"

                    HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Perch.focus(root.pending[0]?.sid ?? "") }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.min(code.implicitHeight, 110) + 18
                radius: 12
                color: "#16171b"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.05)
                clip: true

                Text {
                    id: code

                    x: 10
                    y: 9
                    width: parent.width - 20
                    text: root.pending[0]?.full ?? ""
                    color: "#e8e9ec"
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 7
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                spacing: 6

                Pill {
                    text: "Deny"
                    key: "N"
                    onClicked: root.decide("deny")
                }
                Pill {
                    visible: root.pending[0]?.always ?? false
                    text: "Always"
                    onClicked: root.decide("allow", true)
                }
                Pill {
                    text: "Allow"
                    key: "Y"
                    primary: true
                    onClicked: root.decide("allow")
                }
            }
            Dim {
                Layout.fillWidth: true
                visible: !!root.pending[0]?.rule
                text: `Always adds ${root.pending[0]?.rule ?? ""}`
                font.pixelSize: 11
            }
        }
    }

    Component {
        id: finishedView

        ColumnLayout {
            readonly property var sess: Perch.map[root.finishedSid]

            spacing: 8

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: parent.sess?.name ?? "Claude"
                sub: "is done"
                dot: "#34d399"
            }
            Label {
                Layout.fillWidth: true
                text: parent.sess?.text || "Finished."
                color: "#c0c4cc"
                font.pixelSize: 12
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            RowLayout {
                spacing: 6

                Pill {
                    text: "Show terminal"
                    onClicked: {
                        Perch.focus(root.finishedSid);
                        root.collapse();
                    }
                }
                Pill {
                    text: "OK"
                    primary: true
                    onClicked: root.collapse()
                }
            }
        }
    }

    Component {
        id: limitView

        ColumnLayout {
            readonly property var five: Perch.limits.five_hour
            readonly property var week: Perch.limits.seven_day

            spacing: 8

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: "Usage is getting high"
                dot: "#fb923c"
            }
            Repeater {
                model: [["5-hour window", parent.five], ["This week", parent.week]].filter(x => x[1])

                ColumnLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 3

                    RowLayout {
                        Dim { text: modelData[0]; Layout.fillWidth: true }
                        Text {
                            text: `${modelData[1].used}%`
                            color: modelData[1].used >= 90 ? "#f4505e" : modelData[1].used >= Perch.cfg.limitWarn ? "#fb923c" : "#e8e9ec"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 5
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.08)

                        Rectangle {
                            width: parent.width * Math.min(1, modelData[1].used / 100)
                            height: parent.height
                            radius: 3
                            color: modelData[1].used >= 90 ? "#f4505e" : "#fb923c"
                        }
                    }
                    Dim {
                        visible: !!modelData[1].resets
                        text: modelData[1].resets ? `resets ${Qt.formatDateTime(new Date(modelData[1].resets * 1000), "ddd h:mm ap")}` : ""
                    }
                }
            }
        }
    }

    Component {
        id: askView

        ColumnLayout {
            spacing: 8

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: "Ask Claude"
                sub: "runs claude -p on your plan"
                dot: "#8b5cf6"
            }

            Flow {
                Layout.fillWidth: true
                spacing: 4
                visible: root.files.length > 0

                Repeater {
                    model: root.files

                    Rectangle {
                        required property string modelData

                        width: Math.min(fname.implicitWidth + 16, 200)
                        height: 22
                        radius: 11
                        color: Qt.rgba(1, 1, 1, 0.08)

                        Text {
                            id: fname

                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, 184)
                            text: modelData.split("/").pop()
                            color: "#c0c4cc"
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 19
                color: "#16171b"
                border.width: 1
                border.color: input.activeFocus ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.06)

                TextInput {
                    id: input

                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#e8e9ec"
                    font.pixelSize: 13
                    clip: true
                    focus: true
                    Component.onCompleted: forceActiveFocus()
                    onAccepted: {
                        Perch.ask(text, root.files);
                        root.forcedView = "result";
                    }
                    Keys.onEscapePressed: root.collapse()

                    Text {
                        visible: !input.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.files.length ? "What about it?" : "Ask anything…"
                        color: "#5f646d"
                        font.pixelSize: 13
                    }
                }
            }
            Dim {
                text: "Click the box first if typing does nothing · Esc closes"
                font.pixelSize: 11
            }
        }
    }

    Component {
        id: resultView

        ColumnLayout {
            spacing: 8

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: Perch.asking ? "Claude is thinking…" : Perch.askError ? "Something went wrong" : "Claude says"
                dot: Perch.askError ? "#f4505e" : "#8b5cf6"
                opacity: Perch.asking ? shimmer2.value : 1

                QtObject {
                    id: shimmer2

                    property real value: 1

                    SequentialAnimation on value {
                        loops: Animation.Infinite
                        running: Perch.asking
                        NumberAnimation { to: 0.4; duration: 800 }
                        NumberAnimation { to: 1; duration: 800 }
                    }
                }
            }

            Flickable {
                Layout.fillWidth: true
                implicitHeight: Math.min(answer.implicitHeight, 200)
                contentHeight: answer.implicitHeight
                clip: true
                visible: !Perch.asking

                TextEdit {
                    id: answer

                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: Perch.askError || Perch.answer
                    color: Perch.askError ? "#ff8d97" : "#d6d9de"
                    font.pixelSize: 13
                    textFormat: TextEdit.MarkdownText
                }
            }

            RowLayout {
                spacing: 6
                visible: !Perch.asking

                Pill {
                    text: "Copy"
                    onClicked: Quickshell.execDetached(["wl-copy", Perch.answer])
                }
                Pill {
                    text: "Ask again"
                    onClicked: root.expand("ask")
                }
                Pill {
                    text: "Close"
                    primary: true
                    onClicked: root.collapse()
                }
            }
            Pill {
                visible: Perch.asking
                text: "Stop"
                onClicked: Perch.cancelAsk()
            }
        }
    }

    Component {
        id: fileView

        ColumnLayout {
            spacing: 8

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: root.files.length === 1 ? root.files[0].split("/").pop() : `${root.files.length} files`
                sub: "Maple has it"
                dot: "#34d399"
            }
            RowLayout {
                spacing: 6

                Pill {
                    text: "Ask about it"
                    primary: true
                    onClicked: root.forcedView = "ask"
                }
                Pill {
                    text: "Copy path"
                    onClicked: {
                        Quickshell.execDetached(["wl-copy", root.files.join(" ")]);
                        root.collapse();
                    }
                }
            }
        }
    }

    Component {
        id: dropView

        Rectangle {
            implicitHeight: 96
            radius: 16
            color: Qt.rgba(0.2, 0.83, 0.6, 0.08)
            border.width: 1.5
            border.color: "#34d399"

            Label {
                anchors.centerIn: parent
                text: "Drop it here"
                color: "#a7f3d0"
            }
        }
    }
}
