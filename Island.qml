pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// The island: a dark rounded shape that grows out of its corner of the screen.
//
//   hidden    a small nub; nothing is running
//   peek      cursor touched the nub: Emba pops out and waves
//   compact   a pill while sessions run: Emba, the latest action, a dot per session
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
    property string petNote: ""
    property real tossX: 400

    Timer {
        id: noteTimer

        interval: 3000
        onTriggered: root.petNote = ""
    }

    readonly property var sessions: App.sessions
    readonly property var pending: App.pending
    readonly property var focusSession: sessions[0]

    readonly property string mode: open ? "expanded" : (peeking || App.voiceState !== "") ? "peek" : (sessions.length || dragging || !App.cfg.hideWhenIdle) ? "compact" : "hidden"
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
    readonly property bool sticky: ["approval", "ask", "result", "file", "drop", "listen", "care"].includes(view) || App.asking || App.voiceState !== ""

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
        target: App

        function onPermissionAsked() {
            panda.surprise();
            if (App.cfg.autoOpenOnPermission)
                root.expand(root.forcedView === "ask" ? "ask" : "");
        }
        function onFinished(sid) {
            if (!App.cfg.celebrate || (root.open && root.view !== "overview"))
                return;
            root.finishedSid = sid;
            root.expand("finished");
            if (!hover.hovered)
                autoClose.restart();
        }
        function onLimitWarning(window, percent) {
            panda.emote("surprised", 1);
            if (!root.open || root.view === "overview") {
                root.expand("limit");
                autoClose.restart();
            }
        }
        function onToggleRequested() {
            root.open ? root.collapse() : root.expand();
        }
        function onCareRequested() {
            root.expand("care");
        }
        function onAskRequested() {
            root.expand("ask");
        }
        function onCaptured(path) {
            root.files = [path];
            panda.surprise();
            root.expand("ask");
        }
        function onListenRequested() {
            if (!root.pending.length)
                root.expand("listen");
        }
        function onHeardChanged() {
            // a question goes on to the answer; a command (feed, play...) already moved on
            Qt.callLater(() => {
                if (App.heard && App.asking && root.forcedView === "listen" && !root.pending.length)
                    root.forcedView = "result";
                else if (root.forcedView === "listen" && !App.voiceError)
                    root.collapse();
            });
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

        interval: App.cfg.collapseDelay ?? 1200
        onTriggered: if (!root.sticky)
            root.collapse()
    }

    // ---- mood: what Emba shows ----
    readonly property string mood: {
        if (dragging)
            return "idle";
        if (pending.length)
            return "waiting";
        if (App.voiceState === "listening")
            return "listening";
        if (App.voiceState === "speaking")
            return "idle";
        if (App.asking)
            return "thinking";
        if (open && view === "finished")
            return "done";
        if (open && view === "limit")
            return "limit";
        const s = focusSession;
        // nothing to work on: Emba is just a pet
        if (!s || s.state === "idle") {
            if (Pet.napping)
                return "sleeping";
            if (Pet.need && !(s && Math.max(App.limits.five_hour?.used ?? 0, App.limits.seven_day?.used ?? 0) >= App.cfg.limitWarn))
                return Pet.need;
        }
        if (!s)
            return "idle";
        if (s.state === "idle" && Math.max(App.limits.five_hour?.used ?? 0, App.limits.seven_day?.used ?? 0) >= App.cfg.limitWarn)
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
            color: Qt.alpha(Theme.base, root.mode === "hidden" ? 0.75 : 0.96)
            border.width: 1
            border.color: Qt.alpha(Theme.text, root.mode === "hidden" ? 0.12 : 0.07)
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
                border.color: Theme.warn
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
                            panda.wave();
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
                // closed: open up. On the care view: toss a ball from where you clicked
                onTapped: eventPoint => {
                    if (!root.open)
                        return root.expand();
                    const q = eventPoint.position;
                    const onEmba = q.x >= panda.x && q.x <= panda.x + panda.width && q.y >= panda.y && q.y <= panda.y + panda.height;
                    if (root.view === "care" && !Pet.napping && !onEmba) {
                        root.tossX = eventPoint.position.x;
                        Pet.play();
                    }
                }
            }

            // files dragged in from a file manager
            DropArea {
                anchors.fill: parent
                onEntered: drag => {
                    root.dragging = true;
                    panda.emote("surprised", 30);
                }
                onExited: {
                    root.dragging = false;
                    panda.emote("", 0);
                }
                onDropped: drop => {
                    root.dragging = false;
                    const paths = drop.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter(p => p.startsWith("/"));
                    if (!paths.length)
                        return;
                    root.files = paths;
                    panda.gulp();
                    root.expand("file");
                }
            }

            // ---- Emba, one instance travelling between modes ----
            Panda {
                id: panda

                property real px: root.mode === "expanded" ? 96 : root.mode === "peek" ? 70 : root.mode === "compact" ? 46 : 20

                width: px
                height: px
                x: root.mode === "expanded" ? 12 : root.mode === "compact" ? 2 : (shape.width - px) / 2
                y: root.mode === "expanded" ? Math.min(18, (shape.height - px) / 2) : (shape.height - px) / 2 + (root.mode === "compact" ? 1 : 0)
                opacity: root.mode === "hidden" ? 0 : 1
                running: root.mode !== "hidden"
                mood: root.mood
                talk: App.voiceState === "speaking" ? App.voiceLevel : 0
                bodyColor: App.cfg.color

                Behavior on px { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic } }
                Behavior on x { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic } }
                Behavior on y { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }

                gaze: toy.visible ? Qt.point(toy.x + toy.width / 2 - x - width / 2, toy.y + toy.height / 2 - y - height / 2) : hover.hovered ? Qt.point(hover.point.position.x - x - width / 2, hover.point.position.y - y - height / 2) : cursor.gaze

                onClicked: Pet.napping ? Pet.nap() : !root.open ? root.expand() : root.view === "care" ? boop() : root.expand("care")
                onDoubleClicked: {
                    root.expand("care");
                    Pet.feed();
                }
                onHeld: {
                    root.expand("care");
                    if (!Pet.napping)
                        Pet.nap();
                }
                onPetted: Pet.pet()
            }

            // ---- pet things: a ball to chase, a bamboo snack ----
            Rectangle {
                id: toy

                width: 12
                height: 12
                radius: 6
                visible: false
                color: "#ffd166"
                border.width: 2
                border.color: "#f4a259"

                SequentialAnimation {
                    id: playAnim

                    onStarted: toy.visible = true
                    onFinished: {
                        toy.visible = false;
                        panda.emote("happy", 1.2);
                    }

                    // bounces across the island and back; Emba's eyes follow it
                    ParallelAnimation {
                        NumberAnimation { target: toy; property: "x"; from: root.tossX - 6; to: 8; duration: 1300; easing.type: Easing.InOutQuad }
                        SequentialAnimation {
                            loops: 3
                            NumberAnimation { target: toy; property: "y"; from: shape.height - 22; to: 10; duration: 210; easing.type: Easing.OutQuad }
                            NumberAnimation { target: toy; property: "y"; to: shape.height - 22; duration: 220; easing.type: Easing.InQuad }
                        }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: toy; property: "x"; to: shape.width - 24; duration: 1300; easing.type: Easing.InOutQuad }
                        SequentialAnimation {
                            loops: 3
                            NumberAnimation { target: toy; property: "y"; to: 10; duration: 210; easing.type: Easing.OutQuad }
                            NumberAnimation { target: toy; property: "y"; to: shape.height - 22; duration: 220; easing.type: Easing.InQuad }
                        }
                    }
                }
            }

            Rectangle {
                id: snack

                width: 6
                height: 22
                radius: 3
                visible: false
                color: "#7cc46a"
                rotation: 20

                Rectangle {
                    y: 7
                    width: parent.width
                    height: 2
                    color: "#4f9b45"
                }
                Rectangle {
                    x: 3
                    y: -6
                    width: 8
                    height: 5
                    radius: 3
                    rotation: -30
                    color: "#9be07f"
                }

                SequentialAnimation {
                    id: feedAnim

                    onStarted: snack.visible = true
                    onFinished: {
                        snack.visible = false;
                        panda.gulp();
                    }

                    // drops from the top straight into Emba's mouth
                    PropertyAction { target: snack; property: "x"; value: panda.x + panda.width / 2 - 3 }
                    NumberAnimation { target: snack; property: "y"; from: -24; to: panda.y + panda.height * 0.55; duration: 650; easing.type: Easing.InQuad }
                }
            }

            Connections {
                target: Pet

                function onFed() {
                    panda.emote("surprised", 0.6);
                    feedAnim.restart();
                }
                function onPlayed() {
                    playAnim.restart();
                }
                function onRefused(why) {
                    // a polite no: shake the head, say why
                    panda.shakeHead();
                    root.petNote = why === "full" ? "is full, maybe later" : "is too tired to play";
                    noteTimer.restart();
                }
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
                    text: root.pending.length ? `${root.pending[0].name} needs you` : root.dragging ? "Drop it on Emba" : root.focusSession ? (root.focusSession.ticker.slice(-1)[0] ?? root.focusSession.name) : ""
                    color: root.pending.length ? Theme.warn : Theme.text
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
                            color: App.stateColours[modelData.state] ?? Theme.dim
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
                        drop: dropView,
                        listen: listenView,
                        care: careView
                    })[App.asking && root.view === "ask" ? "result" : root.view] ?? emptyView

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
                color: closeHover.hovered ? Theme.text : Theme.faint
                font.pixelSize: 12

                HoverHandler { id: closeHover }
                TapHandler { onTapped: root.collapse() }
            }
            Text {
                visible: root.mode === "expanded" && root.view !== "approval"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                text: "⚙"
                color: gearHover.hovered ? Theme.text : Theme.faint
                font.pixelSize: 13

                HoverHandler { id: gearHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        App.settingsOpen = true;
                        App.refreshStatus();
                    }
                }
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
        App.decide(req.id, behavior, always);
        App.voiceHint = "";
        if (behavior === "allow")
            panda.emote("happy", 1);
        else
            panda.emote("annoyed", 0.8);
        if (pending.length === 0 && !hover.hovered)
            leaveTimer.restart();
    }

    // ---- the cursor, anywhere on screen ----
    // Wayland hides the global cursor from clients, so on Hyprland we ask the
    // compositor; the desktop host (Windows, macOS, X11) can read it directly.
    QtObject {
        id: cursor

        property var gaze: null
        readonly property bool hostCursor: typeof Quickshell.cursorPos === "function"
        // shaking to talk needs the cursor even while the island is hidden
        readonly property bool wanted: ((App.cfg.trackCursor ?? true) && root.mode !== "hidden") || (!!App.cfg.voice && !!App.cfg.voiceShake)
        property var trail: []

        function aim(x, y) {
            // mapToItem(null) is already in window pixels, scale included
            const c = panda.mapToItem(null, panda.width / 2, panda.height / 2);
            gaze = Qt.point(x - root.origin.x - c.x, y - root.origin.y - c.y);
            if (App.cfg.voice && App.cfg.voiceShake)
                shake(x);
        }

        // A shake is the cursor swinging left-right at least 4 times, each
        // swing over 60 px, within 0.9 s. Ordinary pointing never does that.
        function shake(x) {
            const now = Date.now();
            trail = trail.filter(p => now - p.t < 900).concat([{
                        x: x,
                        t: now
                    }]);
            let turns = 0, dir = 0, from = trail[0].x;
            for (let i = 1; i < trail.length; i++) {
                const d = trail[i].x - trail[i - 1].x;
                if (Math.abs(d) < 4)
                    continue;
                const s = Math.sign(d);
                if (dir && s !== dir) {
                    if (Math.abs(trail[i - 1].x - from) > 60)
                        turns++;
                    from = trail[i - 1].x;
                }
                dir = s;
            }
            if (turns >= 4 && App.voiceState === "") {
                trail = [];
                panda.surprise();
                App.listen();
            }
        }
    }

    Process {
        running: cursor.wanted && !cursor.hostCursor && !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
        command: ["sh", "-c", "while hyprctl cursorpos; do sleep 0.08; done"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/(-?\d+),\s*(-?\d+)/);
                if (m)
                    cursor.aim(+m[1], +m[2]);
            }
        }
        onRunningChanged: if (!running)
            cursor.gaze = null
    }

    Timer {
        running: cursor.wanted && cursor.hostCursor
        interval: 60
        repeat: true
        onTriggered: {
            const p = Quickshell.cursorPos();
            cursor.aim(p.x, p.y);
        }
        onRunningChanged: if (!running)
            cursor.gaze = null
    }

    // clipboard that works on every host
    TextEdit {
        id: clip

        visible: false
    }
    function copy(text) {
        clip.text = text;
        clip.selectAll();
        clip.copy();
    }

    // ================================================================ views

    component Label: Text {
        color: Theme.text
        font.pixelSize: 13
        wrapMode: Text.Wrap
    }

    component Dim: Text {
        color: Theme.dim
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    component Pill: Rectangle {
        id: pill

        property string text
        property string key
        property bool primary
        // voice pointed at this button: it pulses, but still needs a click
        property bool hinted
        signal clicked

        implicitWidth: row.implicitWidth + 24
        implicitHeight: 30
        radius: 15
        color: primary ? (ph.hovered ? Qt.lighter(Theme.primary, 1.08) : Theme.primary) : Qt.alpha(Theme.text, ph.hovered ? 0.15 : 0.09)
        scale: tap.pressed ? 0.94 : hinted ? hintPulse.value : 1
        border.width: hinted ? 2 : 0
        border.color: Theme.warn

        QtObject {
            id: hintPulse

            property real value: 1

            SequentialAnimation on value {
                running: pill.hinted
                loops: Animation.Infinite
                NumberAnimation { to: 1.08; duration: 380; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 380; easing.type: Easing.InOutSine }
            }
        }

        Behavior on scale { NumberAnimation { duration: 90 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.primary ? Theme.onPrimary : Theme.text
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
                border.color: pill.primary ? Qt.alpha(Theme.onPrimary, 0.25) : Qt.alpha(Theme.text, 0.25)

                Text {
                    anchors.centerIn: parent
                    text: pill.key
                    color: pill.primary ? Theme.onPrimary : Theme.dim
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
        property color dot: Theme.dim

        spacing: 6

        Rectangle {
            width: 7
            height: 7
            radius: 4
            color: parent.dot
        }
        Text {
            text: parent.title
            color: Theme.text
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
                    const l = App.limits;
                    const parts = [];
                    if (l.five_hour)
                        parts.push(`5h ${l.five_hour.used}%`);
                    if (l.seven_day)
                        parts.push(`7d ${l.seven_day.used}%`);
                    return parts.join(" · ");
                }
                dot: Theme.ok
            }

            Repeater {
                model: root.sessions.slice(0, 5)

                Rectangle {
                    id: srow

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 12
                    color: Qt.alpha(Theme.text, rh.hovered ? 0.08 : 0.04)

                    HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: App.focus(srow.modelData.sid) }

                    Rectangle {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: App.stateColours[srow.modelData.state] ?? Theme.dim

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
                            text: `${srow.modelData.name} · ${srow.modelData.agent ?? "claude"}`
                            color: Theme.text
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

            // panels from QML plugins
            Repeater {
                model: App.pluginViews

                Loader {
                    required property string modelData

                    Layout.fillWidth: true
                    source: modelData
                    onLoaded: {
                        item.app = App;
                        item.theme = Theme;
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Pill {
                    text: `Ask ${App.askLabel}`
                    onClicked: root.expand("ask")
                }
                Pill {
                    text: "⛶ Look"
                    onClicked: App.look()
                }
                Repeater {
                    model: App.actionsFor(root.sessions[0]?.sid ?? "")

                    Pill {
                        required property var modelData

                        text: modelData.label
                        onClicked: Quickshell.execDetached(modelData.argv)
                    }
                }
            }
        }
    }

    Component {
        id: emptyView

        ColumnLayout {
            id: empty

            // first run: offer to connect before anything else
            readonly property bool connected: App.connected !== false

            spacing: 10

            Label {
                Layout.fillWidth: true
                Layout.topMargin: 8
                text: empty.connected ? "Nothing running right now." : "Hi, I'm Emba!"
                font.pixelSize: 14
            }
            Dim {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: empty.connected ? "Start an agent in a terminal, or ask here." : "Connect me to your coding agents (Claude Code, Codex, opencode, Gemini) and I'll watch your sessions and ask before anything runs."
            }
            Row {
                spacing: 6

                Pill {
                    visible: !empty.connected
                    text: App.busy ? "Connecting…" : "Connect"
                    primary: true
                    onClicked: App.run(["connect"])
                }
                Pill {
                    text: `Ask ${App.askLabel}`
                    primary: empty.connected
                    onClicked: root.expand("ask")
                }
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
                    title: root.pending[0] ? `${root.pending[0].name} · ${root.pending[0].agent}` : ""
                    sub: root.pending.length > 1 ? `wants to use ${root.pending[0]?.tool} · 1 of ${root.pending.length}` : `wants to use ${root.pending[0]?.tool}`
                    dot: Theme.warn
                }
                Dim {
                    text: "terminal ↗"
                    color: th.hovered ? Theme.text : Theme.dim

                    HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: App.focus(root.pending[0]?.sid ?? "") }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.min(code.implicitHeight, 110) + 18
                radius: 12
                color: Theme.surface
                border.width: 1
                border.color: Qt.alpha(Theme.text, 0.05)
                clip: true

                Text {
                    id: code

                    x: 10
                    y: 9
                    width: parent.width - 20
                    text: root.pending[0]?.full ?? ""
                    color: Theme.text
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
                    hinted: App.voiceHint === "deny"
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
                    hinted: App.voiceHint === "allow"
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
            readonly property var sess: App.map[root.finishedSid]

            spacing: 8

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: parent.sess?.name ?? "Your agent"
                sub: "is done"
                dot: Theme.ok
            }
            Label {
                Layout.fillWidth: true
                text: parent.sess?.text || "Finished."
                color: Theme.dim
                font.pixelSize: 12
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            RowLayout {
                spacing: 6

                Pill {
                    text: "Show terminal"
                    onClicked: {
                        App.focus(root.finishedSid);
                        root.collapse();
                    }
                }
                Repeater {
                    model: App.actionsFor(root.finishedSid)

                    Pill {
                        required property var modelData

                        text: modelData.label
                        onClicked: Quickshell.execDetached(modelData.argv)
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
            readonly property var five: App.limits.five_hour
            readonly property var week: App.limits.seven_day

            spacing: 8

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: "Usage is getting high"
                dot: Theme.limit
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
                            color: modelData[1].used >= 90 ? Theme.error : modelData[1].used >= App.cfg.limitWarn ? Theme.limit : Theme.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 5
                        radius: 3
                        color: Qt.alpha(Theme.text, 0.08)

                        Rectangle {
                            width: parent.width * Math.min(1, modelData[1].used / 100)
                            height: parent.height
                            radius: 3
                            color: modelData[1].used >= 90 ? Theme.error : Theme.limit
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
                title: `Ask ${App.askLabel}`
                sub: "on your own account"
                dot: Theme.thinking
            }

            // switch who answers; only tools that are installed show up
            Flow {
                Layout.fillWidth: true
                spacing: 4
                visible: (App.status.ask ?? []).length > 1

                Repeater {
                    model: App.status.ask ?? []

                    Rectangle {
                        required property string modelData
                        readonly property bool on: App.askTool === modelData

                        width: chip.implicitWidth + 16
                        height: 22
                        radius: 11
                        color: on ? Theme.thinking : Qt.alpha(Theme.text, chipHover.hovered ? 0.12 : 0.06)

                        Behavior on color { ColorAnimation { duration: 140 } }

                        Text {
                            id: chip

                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.on ? Theme.onPrimary : Theme.dim
                            font.pixelSize: 11
                            font.weight: parent.on ? Font.DemiBold : Font.Normal
                        }
                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: App.setCfg({ askWith: parent.modelData }) }
                    }
                }
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
                        color: Qt.alpha(Theme.text, 0.08)

                        Text {
                            id: fname

                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, 184)
                            text: modelData.split("/").pop()
                            color: Theme.dim
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
                color: Theme.surface
                border.width: 1
                border.color: input.activeFocus ? Qt.alpha(Theme.text, 0.18) : Qt.alpha(Theme.text, 0.06)

                TextInput {
                    id: input

                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font.pixelSize: 13
                    clip: true
                    focus: true
                    Component.onCompleted: forceActiveFocus()
                    onAccepted: {
                        App.heard = "";
                        App.ask(text, root.files);
                        root.forcedView = "result";
                    }
                    Keys.onEscapePressed: root.collapse()

                    Text {
                        visible: !input.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.files.length ? "What about it?" : "Ask anything…"
                        color: Theme.faint
                        font.pixelSize: 13
                    }
                }
            }
            RowLayout {
                spacing: 6

                Pill {
                    visible: !!App.cfg.voice
                    text: "🎤 Talk"
                    onClicked: App.listen()
                }
                Pill {
                    text: "⛶ Look at screen"
                    onClicked: App.look()
                }
                Dim {
                    Layout.fillWidth: true
                    text: "Esc closes"
                    font.pixelSize: 11
                }
            }
        }
    }

    Component {
        id: careView

        ColumnLayout {
            spacing: 10

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: "Emba"
                sub: root.petNote || (Pet.napping ? "is napping. Shh…" : {
                    hungry: "is hungry",
                    sleepy: "is getting sleepy",
                    lonely: "missed you"
                }[Pet.need] ?? "is happy you're here")
                dot: Pet.need ? Theme.warn : Theme.ok
            }

            // no buttons: Emba is looked after with the mouse (and voice)
            Dim {
                Layout.fillWidth: true
                text: Pet.napping ? "Click Emba to wake it up." : "Rub to pet · double-click to feed · click here to toss a ball · hold to tuck in"
                wrapMode: Text.Wrap
                font.pixelSize: 11
            }
        }
    }

    Component {
        id: listenView

        ColumnLayout {
            spacing: 10

            Header {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                title: App.voiceState === "thinking" ? "Got it…" : App.voiceError ? "Didn't catch that" : "Listening"
                sub: App.voiceError || (App.voiceState === "listening" ? "talk, then pause" : "")
                dot: App.voiceError ? Theme.error : Theme.working
            }

            // a little equaliser that follows the microphone
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                visible: App.voiceState === "listening"

                Repeater {
                    model: 9

                    Rectangle {
                        required property int index
                        readonly property real k: 1 - Math.abs(index - 4) / 5

                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 6 + 34 * App.voiceLevel * k * (0.6 + 0.4 * Math.abs(Math.sin(index * 1.7 + App.voiceLevel * 9)))
                        radius: 3
                        color: Theme.working

                        Behavior on height { NumberAnimation { duration: 90 } }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: App.heard !== ""
                text: `“${App.heard}”`
                color: Theme.dim
                font.italic: true
            }

            RowLayout {
                spacing: 6

                Pill {
                    visible: App.voiceState === ""
                    text: "Try again"
                    primary: true
                    onClicked: App.listen()
                }
                Pill {
                    text: "Type instead"
                    onClicked: root.expand("ask")
                }
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
                title: App.asking ? `${App.askLabel} is thinking…` : App.askError ? "Something went wrong" : `${App.askLabel} says`
                dot: App.askError ? Theme.error : Theme.thinking
                opacity: App.asking ? shimmer2.value : 1

                QtObject {
                    id: shimmer2

                    property real value: 1

                    SequentialAnimation on value {
                        loops: Animation.Infinite
                        running: App.asking
                        NumberAnimation { to: 0.4; duration: 800 }
                        NumberAnimation { to: 1; duration: 800 }
                    }
                }
            }

            Dim {
                Layout.fillWidth: true
                visible: App.heard !== ""
                text: `you said: “${App.heard}”`
                font.italic: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
            }

            Flickable {
                Layout.fillWidth: true
                implicitHeight: Math.min(answer.implicitHeight, 200)
                contentHeight: answer.implicitHeight
                clip: true
                visible: !App.asking

                TextEdit {
                    id: answer

                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: App.askError || App.answer
                    color: App.askError ? Theme.error : Theme.text
                    font.pixelSize: 13
                    textFormat: TextEdit.MarkdownText
                }
            }

            RowLayout {
                spacing: 6
                visible: !App.asking

                Pill {
                    text: "Copy"
                    onClicked: root.copy(App.answer)
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
                visible: App.asking
                text: "Stop"
                onClicked: App.cancelAsk()
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
                sub: "Emba has it"
                dot: Theme.ok
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
                        root.copy(root.files.join(" "));
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
            color: Qt.alpha(Theme.ok, 0.08)
            border.width: 1.5
            border.color: Theme.ok

            Label {
                anchors.centerIn: parent
                text: "Drop it here"
                color: Theme.ok
            }
        }
    }
}
