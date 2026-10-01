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
    // which screen edges the island sits flush against (no margin on that side)
    readonly property bool edgeTop: vAlign === 0 && (App.cfg.marginY ?? 0) === 0
    readonly property bool edgeBottom: vAlign === 1 && (App.cfg.marginY ?? 0) === 0
    readonly property bool edgeLeft: hAlign === 0 && (App.cfg.marginX ?? 0) === 0
    readonly property bool edgeRight: hAlign === 1 && (App.cfg.marginX ?? 0) === 0

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

    // busy: something is working, asking or just finished. Otherwise Emba
    // tucks away into its corner until the mouse comes looking.
    readonly property bool busy: pending.length > 0 || sessions.some(s => ["working", "thinking", "waiting", "done"].includes(s.state))
    readonly property string mode: open ? "expanded" : (peeking || App.voiceState !== "") ? "peek" : (busy || dragging || !App.cfg.hideWhenIdle) ? "compact" : "hidden"
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
    // what you are typing in the ask box; an empty ask box is not worth holding open
    property string draft: ""
    readonly property bool sticky: ["approval", "result", "file", "drop", "listen"].includes(view) || (view === "ask" && draft !== "") || App.asking || App.voiceState !== ""

    function expand(v) {
        forcedView = v ?? "";
        open = true;
        peeking = false;
        leaveTimer.stop();
    }
    function collapse() {
        draft = "";
        playAnim.stop();
        App.followUp = false;
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
        function onOpenRequested(open) {
            open ? root.expand() : root.collapse();
        }
        function onToggleRequested() {
            root.open ? root.collapse() : root.expand();
        }
        function onSnapshotRequested(path) {
            if (path)
                root.grabToImage(r => r.saveToFile(path));
        }
        function onAnswerRequested() {
            root.expand("result");
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

        // an empty ask box gets a little longer: you may be reaching for the keyboard
        interval: root.view === "ask" ? 5000 : (App.cfg.collapseDelay ?? 1200)
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
            // invisible: just a place to hover. A corner, or a strip along the edge
            return (edgeTop || edgeBottom) && (edgeLeft || edgeRight) ? Qt.size(18, 18) : (edgeTop || edgeBottom) ? Qt.size(180, 6) : (edgeLeft || edgeRight) ? Qt.size(6, 140) : Qt.size(46, 10);
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

        // the visible outline, flush with the screen edges the island touches
        Notch {
            id: notch

            x: shape.x - bodyX
            y: shape.y - bodyY
            width: implicitWidth
            height: implicitHeight
            body: Qt.size(shape.width, shape.height)
            atTop: root.edgeTop
            atBottom: root.edgeBottom
            atLeft: root.edgeLeft
            atRight: root.edgeRight
            radius: root.mode === "expanded" ? 30 : Math.min(shape.height / 2, 22)
            ear: root.mode === "hidden" ? 0 : Math.min(16, shape.height / 3)
            fill: Theme.base
            // a glow along the outline while something waits on you
            stroke: root.pending.length && root.mode !== "expanded" ? Qt.alpha(Theme.warn, pulse.value) : Qt.alpha(Theme.text, 0.06)
            strokeWidth: root.pending.length && root.mode !== "expanded" ? 2 : 1
            opacity: root.mode === "hidden" ? 0 : 1

            Behavior on radius { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            Behavior on ear { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

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

        // a focus scope, so the ask box keeps the keyboard inside it while
        // Y / N / Escape still reach the island when nothing inside wants them
        FocusScope {
            id: shape

            width: root.target.width
            height: root.target.height
            x: (stage.width - width) * root.hAlign
            y: (stage.height - height) * root.vAlign
            clip: true

            Behavior on width { NumberAnimation { duration: root.opening ? 560 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic; easing.overshoot: 1.05 } }
            Behavior on height { NumberAnimation { duration: root.opening ? 560 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic; easing.overshoot: 1.05 } }

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

            // Clicks on the island's background: closed, it opens; on the care
            // view, it tosses a ball from there. A MouseArea *behind* the content
            // (a TapHandler here stole every click from the buttons above it).
            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: mouse => {
                    if (!root.open)
                        return root.expand();
                    if (root.view === "care" && !Pet.napping) {
                        root.tossX = mouse.x;
                        Pet.play();
                    }
                }
            }

            // files dragged in from a file manager
            // Files dragged in: Emba opens wide and watches them; on drop the
            // file flies into its mouth and it gulps.
            DropArea {
                id: dropZone

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
                    panda.emote("", 0);
                    // file:///home/x -> /home/x, file:///C:/x -> C:/x
                    const paths = drop.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\/(\/[A-Za-z]:)/, "$1").replace(/^\/([A-Za-z]:)/, "$1").replace(/^file:\/\//, ""))).filter(p => p.startsWith("/") || /^[A-Za-z]:/.test(p));
                    if (!paths.length)
                        return;
                    root.files = paths;
                    swallow.from = Qt.point(drop.x, drop.y);
                    swallow.restart();
                }
            }

            // the file on its way in
            Rectangle {
                id: morsel

                visible: swallow.running
                width: 18
                height: 22
                radius: 3
                color: "#f4f1ea"
                border.width: 1
                border.color: Qt.alpha("#000000", 0.2)

                // folded corner
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: 6
                    height: 6
                    color: "#d9d4c7"
                }
                Repeater {
                    model: 3

                    Rectangle {
                        required property int index

                        x: 3
                        y: 8 + index * 4
                        width: 11 - index * 2
                        height: 1.5
                        color: "#b8b2a3"
                    }
                }

                SequentialAnimation {
                    id: swallow

                    property point from

                    PropertyAction { target: morsel; property: "x"; value: swallow.from.x - 9 }
                    PropertyAction { target: morsel; property: "y"; value: swallow.from.y - 11 }
                    PropertyAction { target: morsel; property: "scale"; value: 1 }
                    ParallelAnimation {
                        NumberAnimation { target: morsel; property: "x"; to: panda.x + panda.width / 2 - 9; duration: 380; easing.type: Easing.InBack }
                        NumberAnimation { target: morsel; property: "y"; to: panda.y + panda.height * 0.55 - 11; duration: 380; easing.type: Easing.InQuad }
                        NumberAnimation { target: morsel; property: "scale"; to: 0.25; duration: 380; easing.type: Easing.InQuad }
                        NumberAnimation { target: morsel; property: "rotation"; from: -20; to: 200; duration: 380 }
                    }
                    ScriptAction {
                        script: {
                            panda.gulp();
                            root.expand("file");
                        }
                    }
                }
            }

            // ---- Emba, one instance travelling between modes ----
            Panda {
                id: panda

                // sized so the whole drawing (ears, paws, tail, hops) fits each shape
                property real px: root.mode === "expanded" ? 96 : root.mode === "peek" ? 56 : root.mode === "compact" ? 34 : 20

                width: px
                height: px
                x: root.mode === "expanded" ? 12 : root.mode === "compact" ? 8 : (shape.width - px) / 2
                y: root.mode === "expanded" ? Math.min(18, (shape.height - px) / 2) : (shape.height - px) / 2
                opacity: root.mode === "hidden" ? 0 : 1
                running: root.mode !== "hidden"
                mood: root.mood
                talk: App.voiceState === "speaking" ? App.voiceLevel : 0
                eager: root.dragging
                bodyColor: App.cfg.color

                Behavior on px { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic } }
                Behavior on x { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic } }
                Behavior on y { NumberAnimation { duration: root.opening ? 520 : 340; easing.type: root.opening ? Easing.OutBack : Easing.InOutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }

                gaze: dropZone.containsDrag ? Qt.point(dropZone.drag.x - x - width / 2, dropZone.drag.y - y - height / 2) : toy.visible ? Qt.point(toy.x + toy.width / 2 - x - width / 2, toy.y + toy.height / 2 - y - height / 2) : hover.hovered ? Qt.point(hover.point.position.x - x - width / 2, hover.point.position.y - y - height / 2) : cursor.gaze

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
                visible: playAnim.running
                color: "#ffd166"
                border.width: 2
                border.color: "#f4a259"

                SequentialAnimation {
                    id: playAnim

                    onFinished: {
                        // visible follows playAnim.running
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
                visible: feedAnim.running
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

                    onFinished: {
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
                x: 50
                spacing: 8
                opacity: root.mode === "compact" ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: root.mode === "compact" ? 260 : 120 } }

                Text {
                    id: compactLabel

                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 190)
                    elide: Text.ElideRight
                    text: root.pending.length ? `${root.pending[0].name} needs you` : root.dragging ? "Drop it on Emba" : root.focusSession ? (root.plain(root.focusSession.ticker.slice(-1)[0]) || root.focusSession.name) : ""
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
                width: shape.width - (root.view === "approval" ? 132 : 156)  // clear of the ✕ and ⚙ column
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

            // close and settings, stacked in the top-right corner, out of the content's way
            Column {
                visible: root.mode === "expanded" && root.view !== "approval"
                opacity: content.opacity
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 8
                anchors.topMargin: 8
                spacing: 2

                Corner {
                    glyph: "✕"
                    onClicked: root.collapse()
                }
                Corner {
                    glyph: "⚙"
                    onClicked: {
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
    // Kept deliberately quiet: one line of title, the content, and at most a
    // couple of small actions. Words a person would use, not tool names.

    // "Edit Invoice.swift" -> "editing Invoice.swift"
    function plain(line) {
        if (!line)
            return "";
        line = line.replace(/\s+/g, " ").trim();  // one line, however long the command
        if (line.startsWith("› "))
            return `asked: ${line.slice(2)}`;
        if (line.startsWith("needs you: "))
            return line;
        const sp = line.indexOf(" ");
        const tool = sp < 0 ? line : line.slice(0, sp);
        const what = sp < 0 ? "" : line.slice(sp + 1);
        const verb = ({
                Bash: "running",
                shell: "running",
                Edit: "editing",
                MultiEdit: "editing",
                Write: "writing",
                write: "writing",
                edit: "editing",
                apply_patch: "editing",
                Read: "reading",
                read: "reading",
                Grep: "searching for",
                Glob: "looking for",
                grep: "searching for",
                glob: "looking for",
                WebFetch: "reading",
                WebSearch: "searching the web for",
                Task: "asking a helper:",
                TodoWrite: "planning",
                NotebookEdit: "editing"
            })[tool];
        return verb ? `${verb} ${what}`.trim() : line;
    }

    // what a permission request is asking for, in words
    function asks(tool) {
        return ({
                Bash: "wants to run a command",
                shell: "wants to run a command",
                bash: "wants to run a command",
                Edit: "wants to edit a file",
                MultiEdit: "wants to edit a file",
                Write: "wants to create a file",
                edit: "wants to edit a file",
                write: "wants to create a file",
                apply_patch: "wants to change files",
                WebFetch: "wants to open a web page",
                webfetch: "wants to open a web page",
                external_directory: "wants to go outside the project"
            })[tool] ?? `wants to use ${tool}`;
    }

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

    // a small round icon button for the corner
    component Corner: Rectangle {
        id: corner

        property string glyph
        signal clicked

        width: 24
        height: 24
        radius: 12
        color: Qt.alpha(Theme.text, ch.hovered ? 0.1 : 0)

        Text {
            anchors.centerIn: parent
            text: corner.glyph
            color: ch.hovered ? Theme.text : Theme.faint
            font.pixelSize: 12
        }
        HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: corner.clicked() }
    }

    // a word you can click: for everything that is not the main decision
    component Link: Text {
        id: link

        signal clicked

        color: lh.hovered ? Theme.text : Theme.dim
        font.pixelSize: 12
        font.underline: lh.hovered

        HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: link.clicked() }
    }

    component Pill: Rectangle {
        id: pill

        property string text
        property bool primary
        // voice pointed at this button: it pulses, but still needs a click
        property bool hinted
        readonly property bool hovered: ph.hovered
        signal clicked

        implicitWidth: label.implicitWidth + 28
        implicitHeight: 30
        radius: 15
        color: primary ? (ph.hovered ? Qt.lighter(Theme.primary, 1.08) : Theme.primary) : Qt.alpha(Theme.text, ph.hovered ? 0.15 : 0.08)
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

        Text {
            id: label

            anchors.centerIn: parent
            text: pill.text
            color: pill.primary ? Theme.onPrimary : Theme.text
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: pill.clicked() }
    }

    component Title: RowLayout {
        property string title
        property string sub
        property color dot: Theme.dim

        Layout.fillWidth: true
        Layout.rightMargin: 18
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

    // looks like a text box; opens the ask view
    component AskField: Rectangle {
        objectName: "askField"
        Layout.fillWidth: true
        implicitHeight: 32
        radius: 16
        color: Qt.alpha(Theme.text, af.hovered ? 0.09 : 0.05)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 14
            text: `Ask ${App.askLabel}…`
            color: Theme.faint
            font.pixelSize: 13
        }
        HoverHandler { id: af; cursorShape: Qt.IBeamCursor }
        TapHandler { onTapped: root.expand("ask") }
    }

    QtObject {
        id: shimmer

        property real value: 1

        SequentialAnimation on value {
            loops: Animation.Infinite
            NumberAnimation { to: 0.5; duration: 1100; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
        }
    }

    // ---- what's going on ----
    Component {
        id: overviewView

        ColumnLayout {
            spacing: 6

            Title {
                title: root.sessions.length === 1 ? "Working on 1 thing" : `Working on ${root.sessions.length} things`
                dot: Theme.ok
            }

            Repeater {
                model: root.sessions.slice(0, 4)

                Rectangle {
                    id: srow

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 12
                    color: Qt.alpha(Theme.text, rh.hovered ? 0.07 : 0.035)

                    HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: App.focus(srow.modelData.sid) }

                    Rectangle {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 4
                        color: App.stateColours[srow.modelData.state] ?? Theme.dim
                        opacity: ["working", "thinking", "waiting"].includes(srow.modelData.state) ? shimmer.value : 1
                    }

                    Column {
                        x: 27
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 37

                        Text {
                            width: parent.width
                            text: srow.modelData.name
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Dim {
                            width: parent.width
                            text: root.plain(srow.modelData.ticker.slice(-1)[0]) || "ready"
                            font.pixelSize: 11
                        }
                    }
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

            AskField {}
        }
    }

    // ---- nothing running ----
    Component {
        id: emptyView

        ColumnLayout {
            id: empty

            // first run: offer to connect before anything else
            readonly property bool connected: App.connected !== false

            spacing: 10

            Label {
                Layout.topMargin: 6
                text: empty.connected ? "All quiet." : "Hi, I'm Emba!"
                font.pixelSize: 15
                font.weight: Font.Medium
            }
            Dim {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                visible: !empty.connected
                text: "Let me keep an eye on your coding agents."
            }
            Pill {
                visible: !empty.connected
                text: App.busy ? "Connecting…" : "Connect"
                primary: true
                onClicked: App.run(["connect"])
            }
            AskField {
                visible: empty.connected
            }
        }
    }

    // ---- an agent asks before doing something ----
    Component {
        id: approvalView

        ColumnLayout {
            readonly property var req: root.pending[0]

            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Title {
                    Layout.rightMargin: 0
                    title: parent.parent.req?.name ?? ""
                    sub: root.asks(parent.parent.req?.tool ?? "") + (root.pending.length > 1 ? `  (1 of ${root.pending.length})` : "")
                    dot: Theme.warn
                }
                Link {
                    text: "terminal ↗"
                    onClicked: App.focus(root.pending[0]?.sid ?? "")
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.min(code.implicitHeight, 110) + 18
                radius: 12
                color: Theme.surface
                clip: true

                Text {
                    id: code

                    x: 10
                    y: 9
                    width: parent.width - 20
                    text: root.pending[0]?.full ?? ""
                    color: Theme.text
                    font.family: Qt.platform.os === "windows" ? "Consolas" : Qt.platform.os === "osx" ? "Menlo" : "monospace"
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 7
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                spacing: 10

                Pill {
                    text: "Deny"
                    hinted: App.voiceHint === "deny"
                    onClicked: root.decide("deny")
                }
                Pill {
                    id: always

                    visible: root.pending[0]?.always ?? false
                    text: "Always"
                    onClicked: root.decide("allow", true)
                }
                Pill {
                    text: "Allow"
                    primary: true
                    hinted: App.voiceHint === "allow"
                    onClicked: root.decide("allow")
                }
            }
            // what "Always" would remember, shown only while you point at it
            Dim {
                Layout.fillWidth: true
                visible: always.hovered && !!root.pending[0]?.rule
                text: `from now on allows ${root.pending[0]?.rule ?? ""}`
                font.pixelSize: 11
            }
        }
    }

    // ---- a session finished ----
    Component {
        id: finishedView

        ColumnLayout {
            readonly property var sess: App.map[root.finishedSid]

            spacing: 8

            Title {
                title: parent.sess?.name ?? "Your agent"
                sub: "is done"
                dot: Theme.ok
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: parent.sess?.text ?? ""
                color: Theme.dim
                font.pixelSize: 12
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            Flow {
                Layout.fillWidth: true
                spacing: 14

                Link {
                    text: "open terminal ↗"
                    onClicked: {
                        App.focus(root.finishedSid);
                        root.collapse();
                    }
                }
                Repeater {
                    model: App.actionsFor(root.finishedSid)

                    Link {
                        required property var modelData

                        text: modelData.label.toLowerCase()
                        onClicked: Quickshell.execDetached(modelData.argv)
                    }
                }
            }
        }
    }

    // ---- close to a usage limit ----
    Component {
        id: limitView

        ColumnLayout {
            spacing: 8

            Title {
                title: "Running low"
                sub: App.modelLabel ?? ""
                dot: Theme.limit
            }
            Repeater {
                model: [["Right now", App.limits.five_hour], ["This week", App.limits.seven_day]].filter(x => x[1])

                ColumnLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 3

                    RowLayout {
                        Dim {
                            Layout.fillWidth: true
                            text: modelData[0]
                        }
                        Dim {
                            text: modelData[1].resets ? `back ${Qt.formatDateTime(new Date(modelData[1].resets * 1000), "ddd h:mm ap")}` : ""
                            font.pixelSize: 11
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
                }
            }
        }
    }

    // ---- ask ----
    Component {
        id: askView

        ColumnLayout {
            spacing: 8

            // who answers: only tools that are installed show up
            Flow {
                Layout.fillWidth: true
                Layout.rightMargin: 18
                spacing: 4

                Repeater {
                    model: (App.status.ask ?? []).length ? App.status.ask : [App.askTool]

                    Rectangle {
                        required property string modelData
                        readonly property bool on: App.askTool === modelData

                        width: chip.implicitWidth + 18
                        height: 24
                        radius: 12
                        color: on ? Theme.primary : Qt.alpha(Theme.text, chipHover.hovered ? 0.1 : 0.05)

                        Behavior on color { ColorAnimation { duration: 140 } }

                        Text {
                            id: chip

                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.on ? Theme.onPrimary : Theme.dim
                            font.pixelSize: 12
                            font.weight: parent.on ? Font.DemiBold : Font.Normal
                        }
                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: App.setCfg({ askWith: parent.modelData }) }
                    }
                }
            }

            // attached files and screenshots
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
                            text: modelData.split(/[\\/]/).pop()
                            color: Theme.dim
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: 20
                color: Theme.surface
                border.width: 1
                border.color: input.activeFocus ? Qt.alpha(Theme.text, 0.2) : Qt.alpha(Theme.text, 0.06)

                TextInput {
                    id: input

                    objectName: "askInput"

                    anchors.left: parent.left
                    anchors.right: tools.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 8
                    color: Theme.text
                    font.pixelSize: 13
                    clip: true
                    focus: true
                    Component.onCompleted: forceActiveFocus()
                    onTextChanged: root.draft = text
                    onAccepted: {
                        App.heard = "";
                        App.ask(text, root.files);
                        root.forcedView = "result";
                    }
                    Keys.onEscapePressed: root.collapse()

                    Text {
                        visible: !input.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.files.length ? "What about it?" : `Ask ${App.askLabel}…`
                        color: Theme.faint
                        font.pixelSize: 13
                    }
                }

                // talk, or point at something on screen
                Row {
                    id: tools

                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Link {
                        visible: !!App.cfg.voice
                        text: "🎤"
                        font.pixelSize: 15
                        onClicked: App.listen()
                    }
                    Link {
                        text: "⛶"
                        font.pixelSize: 16
                        onClicked: App.look()
                    }
                }
            }
        }
    }

    // ---- the answer ----
    Component {
        id: resultView

        ColumnLayout {
            spacing: 8

            Title {
                title: App.asking ? `${App.askLabel} is thinking…` : App.askError ? "That didn't work" : App.askLabel
                sub: App.heard ? `“${App.heard}”` : ""
                dot: App.askError ? Theme.error : Theme.thinking
                opacity: App.asking ? shimmer.value : 1
            }

            Flickable {
                Layout.fillWidth: true
                implicitHeight: Math.min(answer.implicitHeight, 210)
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

            Flow {
                Layout.fillWidth: true
                spacing: 14

                Link {
                    visible: App.asking
                    text: "stop"
                    onClicked: App.cancelAsk()
                }
                Link {
                    visible: !App.asking && !App.askError
                    text: "copy"
                    onClicked: root.copy(App.answer)
                }
                Link {
                    visible: !App.asking && !App.askError
                    text: "follow up"
                    onClicked: {
                        App.followUp = true;
                        root.files = [];
                        root.expand("ask");
                    }
                }
                Link {
                    visible: !App.asking && !App.askError && App.canContinue
                    text: "continue in terminal ↗"
                    onClicked: App.continueInTerminal()
                }
            }
        }
    }

    // ---- files dropped on Emba ----
    Component {
        id: fileView

        ColumnLayout {
            spacing: 8

            Title {
                title: root.files.length === 1 ? root.files[0].split(/[\\/]/).pop() : `${root.files.length} files`
                dot: Theme.ok
            }
            AskField {}
            Link {
                text: "copy path"
                onClicked: {
                    root.copy(root.files.join(" "));
                    root.collapse();
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
                text: "Feed it to Emba"
                color: Theme.ok
            }
        }
    }

    // ---- looking after Emba ----
    Component {
        id: careView

        ColumnLayout {
            spacing: 8

            Title {
                title: "Emba"
                sub: root.petNote || (Pet.napping ? "is napping" : {
                        hungry: "is hungry",
                        sleepy: "is sleepy",
                        lonely: "missed you"
                    }[Pet.need] ?? "is happy")
                dot: Pet.need ? Theme.warn : Theme.ok
            }
            // no buttons: Emba is looked after with the mouse (and voice)
            Dim {
                Layout.fillWidth: true
                text: Pet.napping ? "Click to wake." : "Rub to pet · double-click to feed\nclick here to throw a ball · hold to tuck in"
                wrapMode: Text.Wrap
                font.pixelSize: 11
                lineHeight: 1.2
            }
        }
    }

    // ---- listening ----
    Component {
        id: listenView

        ColumnLayout {
            spacing: 10

            Title {
                title: App.voiceState === "thinking" ? "Got it…" : App.voiceError ? "Didn't catch that" : "Listening"
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

            Flow {
                Layout.fillWidth: true
                spacing: 14
                visible: App.voiceState === ""

                Link {
                    text: "try again"
                    onClicked: App.listen()
                }
                Link {
                    text: "type instead"
                    onClicked: root.expand("ask")
                }
            }
        }
    }
}
