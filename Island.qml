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
    // on the left or right edge (not a corner) the small pill stands upright
    readonly property bool sideways: (edgeLeft || edgeRight) && !(edgeTop || edgeBottom)

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

    // The island's own palette, like a phone's notch: black, white type, and
    // Emba's fur as the only accent. (Settings still follows the desktop theme.)
    readonly property QtObject ui: QtObject {
        readonly property color bg: "#000000"
        readonly property color text: "#ffffff"
        readonly property color dim: Qt.rgba(1, 1, 1, 0.6)
        readonly property color faint: Qt.rgba(1, 1, 1, 0.36)
        readonly property color fill: Qt.rgba(1, 1, 1, 0.1)
        readonly property color fillHover: Qt.rgba(1, 1, 1, 0.16)
        readonly property color accent: App.cfg.color || "#e2683c"
        readonly property color accentInk: "#ffffff"
        readonly property color error: "#ff453a"
    }
    // where a session lives, without its own name: /home/me/code/invoices -> ~/code
    readonly property string home: Quickshell.env("HOME") ?? ""
    function where(cwd) {
        const parts = String(cwd ?? "").split(/[\\/]/);
        parts.pop();
        const dir = parts.join("/");
        return home && dir.startsWith(home) ? "~" + dir.slice(home.length) : dir;
    }
    // how long a session has been going: 4m, 2h 32m
    property real now: Date.now()
    Timer {
        running: root.open
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
    function age(started) {
        const m = Math.max(0, Math.floor((now - started) / 60000));
        return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${m % 60}m`;
    }
    readonly property var pending: App.pending
    readonly property var focusSession: sessions[0]

    // busy: something is working, asking or just finished. Otherwise Emba
    // tucks away into its corner until the mouse comes looking.
    readonly property bool busy: pending.length > 0 || sessions.some(s => ["working", "thinking", "waiting", "done"].includes(s.state))
    readonly property bool dancing: !!App.music && App.cfg.danceToMusic !== false
    readonly property string mode: open || dragging ? "expanded" : (peeking || App.voiceState !== "") ? "peek" : (busy || dancing || !App.cfg.hideWhenIdle) ? "compact" : sessions.length ? "dots" : "hidden"
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

    // userOpened: you opened it (hover, click, a command) rather than Emba
    // popping up by itself; only then may it take the keyboard and close on
    // a click elsewhere.
    property bool userOpened: false
    // a click on the island since the current request appeared: Y / N need it
    property bool armed: false
    onPendingChanged: armed = false

    function expand(v) {
        forcedView = v ?? "";
        open = true;
        peeking = false;
        userOpened = true;
        leaveTimer.stop();
    }
    function expandAuto(v) {
        const was = open && userOpened;
        expand(v);
        userOpened = was;
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
                root.expandAuto(root.forcedView === "ask" ? "ask" : "");
        }
        function onFinished(sid) {
            if (!App.cfg.celebrate || (root.open && root.view !== "overview"))
                return;
            root.finishedSid = sid;
            root.expandAuto("finished");
            if (!hover.hovered)
                autoClose.restart();
        }
        function onLimitWarning(window, percent) {
            panda.emote("surprised", 1);
            if (!root.open || root.view === "overview") {
                root.expandAuto("limit");
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
            if (!path)
                return;
            if (!path.includes("%d"))
                return root.grabToImage(r => r.saveToFile(path));
            // "frames/%d.png": a second of frames, to check animations
            recorder.path = path;
            recorder.frame = 0;
            recorder.restart();
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

        onTriggered: root.expandAuto()  // hovering never takes the keyboard; a click does
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
            if (Pet.need && !(s && App.maxUsed >= App.cfg.limitWarn))
                return Pet.need;
        }
        if (!s)
            return "idle";
        if (s.state === "idle" && App.maxUsed >= App.cfg.limitWarn)
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
        if (mode === "dots")
            // just the sessions, very small, flush in the corner
            return sideways ? Qt.size(20, 12 + Math.min(sessions.length, 6) * 10) : Qt.size(12 + Math.min(sessions.length, 6) * 10, 20);
        if (mode === "peek")
            return greeting ? Qt.size(122, 70) : Qt.size(76, 70);
        if (mode === "compact")
            return sideways ? Qt.size(44, 52 + Math.min(sessions.length, 6) * 10 + 4) : Qt.size(Math.min(300, 58 + compactLabel.implicitWidth + 14 + Math.min(sessions.length, 6) * 10 + 8), 44);
        return Qt.size(460, Math.max(132, Math.min(360, (content.item?.implicitHeight ?? 100) + 30)));
    }
    readonly property bool opening: mode === "expanded" || mode === "peek"

    // A breath for the dots of busy sessions, stepped at 8 fps by a timer: an
    // endless QML animation would keep the whole island redrawing at full rate.
    property real beat: 0
    Timer {
        running: root.sessions.some(x => ["working", "thinking", "waiting"].includes(x.state)) && (root.mode === "compact" || root.mode === "dots")
        interval: 125
        repeat: true
        onTriggered: root.beat = (root.beat + 0.125) % 1.2
        onRunningChanged: root.beat = 0
    }
    component SessionDot: Rectangle {
        required property var modelData
        readonly property bool active: ["working", "thinking", "waiting"].includes(modelData.state)

        width: 6
        height: 6
        radius: 3
        color: modelData.state === "waiting" ? root.ui.accent : App.agentColour(modelData.agent)
        opacity: active ? 0.55 + 0.45 * Math.sin(root.beat / 1.2 * 2 * Math.PI) ** 2 : 0.6
        scale: active ? 1 + 0.35 * Math.sin(root.beat / 1.2 * 2 * Math.PI) ** 2 : 1
    }
    // hovering the corner: Emba pops out, waves and says hi (as coucou)
    readonly property bool greeting: mode === "peek" && App.voiceState === "" && !sideways

    // Grow on a soft spring, shrink on a 340 ms curve with no overshoot (as coucou).
    // Which one is decided here, from the sizes themselves: a Behavior reading
    // `opening` could start before that binding updated and bounce on the way in.
    function tween(anim, to) {
        const grow = to > anim.target[anim.property];
        anim.stop();
        anim.to = to;
        anim.duration = grow ? 520 : 340;
        anim.easing.type = grow ? Easing.OutBack : Easing.BezierSpline;
        anim.easing.overshoot = 0.9;
        anim.easing.bezierCurve = [0.45, 0, 0.2, 1, 1, 1];
        anim.start();
    }
    onTargetChanged: {
        tween(widthAnim, target.width);
        tween(heightAnim, target.height);
    }
    NumberAnimation { id: widthAnim; target: shape; property: "width" }
    NumberAnimation { id: heightAnim; target: shape; property: "height" }
    NumberAnimation { id: goalAnim; target: panda; property: "goal" }

    Timer {
        id: recorder

        property string path
        property int frame

        interval: 33
        repeat: true
        onTriggered: {
            const n = frame++;
            root.grabToImage(r => r.saveToFile(path.replace("%d", String(n).padStart(2, "0"))));
            if (frame >= 30)
                stop();
        }
    }

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
            radius: Math.min(shape.height / 2, 22 + 8 * Math.max(0, Math.min(1, (shape.height - 44) / 88)))
            ear: Math.min(16, shape.height / 3)
            fill: root.ui.bg
            // a glow along the outline while something waits on you
            stroke: root.pending.length && root.mode !== "expanded" ? Qt.alpha(root.ui.accent, pulse.value) : "transparent"
            strokeWidth: root.pending.length && root.mode !== "expanded" ? 2 : 1
            opacity: root.mode === "hidden" ? 0 : 1

            // the corners follow the shape's size, so they never lag behind it
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

            x: (stage.width - width) * root.hAlign
            y: (stage.height - height) * root.vAlign
            clip: true

            Component.onCompleted: {
                width = root.target.width;
                height = root.target.height;
            }

            HoverHandler {
                id: hover

                onHoveredChanged: {
                    if (hovered) {
                        leaveTimer.stop();
                        unpeek.stop();
                        autoClose.stop();
                        if (root.mode === "hidden" || root.mode === "dots") {
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

            // Notices any click on the island (to arm Y / N) without taking it:
            // a PointHandler only watches, so the buttons still get every click.
            PointHandler {
                acceptedButtons: Qt.LeftButton
                onActiveChanged: if (active) {
                    root.armed = true;
                    if (root.open)
                        root.userOpened = true;
                }
            }

            // Clicks on the island's background: closed, it opens; on the care
            // view, it tosses a ball from there. A MouseArea *behind* the content
            // (a TapHandler here stole every click from the buttons above it).
            MouseArea {
                anchors.fill: parent
                z: -1
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    // right-click anywhere on the island: settings
                    if (mouse.button === Qt.RightButton) {
                        App.settingsOpen = true;
                        return App.refreshStatus();
                    }
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
                    // stay open through the swallow: no snapping back to the pill in between
                    root.expandAuto("drop");
                    root.dragging = false;
                    panda.emote("", 0);
                    // file:///home/x -> /home/x, file:///C:/x -> C:/x
                    const paths = drop.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\/(\/[A-Za-z]:)/, "$1").replace(/^\/([A-Za-z]:)/, "$1").replace(/^file:\/\//, ""))).filter(p => p.startsWith("/") || /^[A-Za-z]:/.test(p));
                    if (!paths.length)
                        return root.collapse();
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
                        NumberAnimation { target: morsel; property: "y"; to: panda.y + panda.height * 0.31 - 11; duration: 380; easing.type: Easing.InQuad }  // into the slot on its head
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

                // sized so the whole drawing (ears, paws, tail, hops) fits each shape;
                // never taller than the island is right now, so it can't poke out mid-animation
                readonly property real goalFor: root.dragging ? 80 : root.mode === "expanded" ? 72 : root.mode === "peek" ? 56 : root.mode === "compact" ? 34 : 20
                property real goal: 20
                onGoalForChanged: root.tween(goalAnim, goalFor)
                readonly property real px: Math.max(0, Math.min(goal, shape.height - 8, shape.width - 8))

                width: px
                height: px
                // A function of the island's size at this very frame, not an animation of
                // its own: Emba rides along with the shape and can never fall behind it.
                readonly property real openness: Math.max(0, Math.min(1, (shape.height - 44) / 88))
                x: (root.mode === "compact" || root.mode === "expanded" || root.greeting) && !root.sideways ? 8 + 6 * openness : (shape.width - px) / 2
                y: root.mode === "compact" && root.sideways ? 6 : Math.min((shape.height - px) / 2, 5 + 13 * openness + (1 - openness) * (shape.height - px) / 2)
                opacity: root.mode === "hidden" || root.mode === "dots" ? 0 : 1
                running: root.mode !== "hidden" && root.mode !== "dots"
                mood: root.mood
                talk: App.voiceState === "speaking" ? App.voiceLevel : 0
                fps: root.mode === "expanded" ? 24 : root.dancing && !root.busy ? 8 : 12
                eager: root.dragging
                music: root.dancing
                bodyColor: App.cfg.color

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

            // ---- peek: hi! once the island has popped out ----
            Text {
                x: 72
                anchors.verticalCenter: parent.verticalCenter
                text: "Hi!"
                color: root.ui.text
                font.pixelSize: 16
                font.weight: Font.DemiBold
                opacity: root.greeting && !widthAnim.running ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            // ---- compact: the latest action and a dot per session ----
            Row {
                id: compactRow

                anchors.verticalCenter: parent.verticalCenter
                x: 50
                spacing: 8
                // back only once the pill has finished shrinking; gone at once when it grows
                opacity: root.mode === "compact" && !root.sideways && !heightAnim.running && !widthAnim.running ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: compactRow.opacity < 0.5 ? 200 : 0 } }

                Text {
                    id: compactLabel

                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 190)
                    elide: Text.ElideRight
                    text: root.pending.length ? `${root.pending[0].name} needs you` : root.dragging ? "Drop it on Emba" : root.busy && root.focusSession ? (root.plain(root.focusSession.ticker.slice(-1)[0]) || root.focusSession.name) : root.dancing ? `♪ ${App.music}` : root.focusSession?.name ?? ""
                    color: root.pending.length ? root.ui.accent : root.ui.text
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: root.sessions.slice(0, 6)

                        SessionDot {}
                    }
                }
            }

            // on a side edge the pill stands upright: Emba on top, a dot per session below
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 46
                spacing: 4
                opacity: root.mode === "compact" && root.sideways ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: 260 } }

                Repeater {
                    model: root.sessions.slice(0, 6)

                    SessionDot {}
                }
            }

            // ---- dots: nothing busy, the sessions still there, very small ----
            Grid {
                anchors.centerIn: parent
                flow: root.sideways ? Grid.TopToBottom : Grid.LeftToRight
                rows: root.sideways ? 6 : 1
                spacing: 4
                opacity: root.mode === "dots" && !widthAnim.running ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: 160 } }

                Repeater {
                    model: root.sessions.slice(0, 6)

                    SessionDot {}
                }
            }

            // ---- expanded views ----
            Loader {
                id: content

                x: 98
                y: 18
                width: shape.width - 98 - (cornerButton.visible ? 52 : 22)
                active: root.mode === "expanded"
                // in once the island is nearly open (never squeezed into a small one), out at once
                opacity: root.mode === "expanded" && shape.height >= Math.min(root.target.height, 132) * 0.85 ? 1 : 0
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

                Behavior on opacity { NumberAnimation { duration: content.opacity < 0.5 ? 220 : 0 } }
            }

            // settings on the main screens; a way back to them from everywhere else
            IconButton {
                id: cornerButton

                objectName: "cornerButton"

                readonly property bool home: ["overview", "empty"].includes(root.view)

                visible: root.mode === "expanded" && !["approval", "drop"].includes(root.view)
                opacity: content.opacity
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 14
                anchors.topMargin: 14
                kind: home ? "gear" : "back"
                onClicked: {
                    if (home) {
                        App.settingsOpen = true;
                        return App.refreshStatus();
                    }
                    if (App.asking)
                        App.cancelAsk();
                    App.followUp = false;
                    root.files = [];
                    root.draft = "";
                    root.expand();
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.collapse();
                } else if (root.view === "approval" && root.pending.length && root.armed) {
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

    // Asked straight over Hyprland's own socket: no process per question,
    // which is what made this expensive when it ran hyprctl in a loop.
    readonly property string hyprSocket: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket.sock` : ""

    Socket {
        id: hypr

        path: root.hyprSocket
        onConnectedChanged: if (connected) {
            write("cursorpos");
            flush();
        }
        parser: SplitParser {
            onRead: line => {
                const m = line.match(/(-?\d+),\s*(-?\d+)/);
                if (m)
                    cursor.aim(+m[1], +m[2]);
            }
        }
    }
    Timer {
        // quicker while shaking could happen or the island is open, slower otherwise
        running: cursor.wanted && !cursor.hostCursor && root.hyprSocket !== ""
        interval: root.mode === "expanded" || root.mode === "peek" ? 70 : 110
        repeat: true
        onTriggered: {
            hypr.connected = false;
            hypr.connected = true;
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
        color: root.ui.text
        font.pixelSize: 14
        wrapMode: Text.Wrap
    }

    component Dim: Text {
        color: root.ui.dim
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    // a round, drawn icon button: "gear" (settings) or "back"
    component IconButton: Rectangle {
        id: ib

        property string kind
        readonly property color ink: ibh.hovered ? root.ui.text : root.ui.dim
        signal clicked

        width: 30
        height: 30
        radius: 15
        color: ibh.hovered ? root.ui.fillHover : root.ui.fill
        scale: ibt.pressed ? 0.9 : 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 90 } }

        // back: a chevron pointing left
        Item {
            visible: ib.kind === "back"
            anchors.fill: parent

            Rectangle { x: 11.5; y: 11.3; width: 8; height: 2; radius: 1; color: ib.ink; rotation: -45; transformOrigin: Item.Left }
            Rectangle { x: 11.5; y: 16.7; width: 8; height: 2; radius: 1; color: ib.ink; rotation: 45; transformOrigin: Item.Left; anchors.verticalCenterOffset: 0 }
        }

        // gear: eight teeth around a ring
        Item {
            visible: ib.kind === "gear"
            anchors.centerIn: parent
            width: 16
            height: 16

            Repeater {
                model: 4

                Rectangle {
                    required property int index
                    anchors.centerIn: parent
                    width: 15
                    height: 3
                    radius: 1
                    rotation: index * 45
                    color: ib.ink
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 11
                height: 11
                radius: 5.5
                color: ib.ink
            }
            // the hole: the button's colour made opaque (it sits on the black island)
            Rectangle {
                anchors.centerIn: parent
                width: 5
                height: 5
                radius: 2.5
                color: ibh.hovered ? "#292929" : "#1a1a1a"
            }
        }

        HoverHandler { id: ibh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: ibt; onTapped: ib.clicked() }
    }

    // a round, drawn icon: "mic" (talk) or "area" (point at the screen)
    component ToolIcon: Rectangle {
        id: ti

        property string kind
        property string hint
        readonly property bool hovered: tih.hovered
        readonly property color ink: tih.hovered ? root.ui.accent : root.ui.dim
        signal clicked

        width: 30
        height: 30
        radius: 15
        color: Qt.alpha(root.ui.text, tih.hovered ? 0.12 : 0.05)
        scale: tit.pressed ? 0.9 : 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 90 } }

        // microphone: capsule, cradle, stand
        Item {
            visible: ti.kind === "mic"
            anchors.fill: parent

            Rectangle { x: 12; y: 6; width: 6; height: 11; radius: 3; color: ti.ink }
            Item {
                x: 9; y: 12; width: 12; height: 7; clip: true
                Rectangle { y: -5; width: 12; height: 12; radius: 6; color: "transparent"; border.width: 1.6; border.color: ti.ink }
            }
            Rectangle { x: 14.2; y: 19; width: 1.6; height: 3; color: ti.ink }
            Rectangle { x: 11.5; y: 22; width: 7; height: 1.6; radius: 0.8; color: ti.ink }
        }

        // a selection: four corner brackets around a small dot
        Item {
            visible: ti.kind === "area"
            anchors.fill: parent

            Repeater {
                model: 4

                Item {
                    required property int index
                    x: index % 2 ? 16 : 7
                    y: index < 2 ? 7 : 16
                    width: 7
                    height: 7

                    Rectangle { y: parent.index < 2 ? 0 : 5.4; width: 7; height: 1.6; radius: 0.8; color: ti.ink }
                    Rectangle { x: parent.index % 2 ? 5.4 : 0; width: 1.6; height: 7; radius: 0.8; color: ti.ink }
                }
            }
            Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: ti.ink }
        }

        HoverHandler { id: tih; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tit; onTapped: ti.clicked() }
    }

    // a small secondary action: everything that is not the main decision
    component Link: Rectangle {
        id: link

        property string text
        signal clicked

        implicitWidth: linkLabel.implicitWidth + 24
        implicitHeight: 28
        radius: 14
        color: lh.hovered ? root.ui.fillHover : root.ui.fill
        scale: lt.pressed ? 0.95 : 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 90 } }

        Text {
            id: linkLabel

            anchors.centerIn: parent
            text: link.text
            color: root.ui.text
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: lt; onTapped: link.clicked() }
    }

    component Pill: Rectangle {
        id: pill

        property string text
        property bool primary
        // voice pointed at this button: it pulses, but still needs a click
        property bool hinted
        readonly property bool hovered: ph.hovered
        signal clicked

        implicitWidth: Math.max(72, label.implicitWidth + 32)
        implicitHeight: 34
        radius: 17
        color: primary ? (ph.hovered ? Qt.lighter(root.ui.accent, 1.1) : root.ui.accent) : (ph.hovered ? root.ui.fillHover : root.ui.fill)
        scale: tap.pressed ? 0.94 : hinted ? hintPulse.value : 1
        border.width: hinted ? 2 : 0
        border.color: root.ui.accent

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
            color: pill.primary ? root.ui.accentInk : root.ui.text
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: pill.clicked() }
    }

    component Title: RowLayout {
        property string title
        property string sub

        Layout.fillWidth: true
        spacing: 8

        Text {
            text: parent.title
            color: root.ui.text
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            text: parent.sub
            color: root.ui.dim
            font.pixelSize: 13
            elide: Text.ElideRight
        }
    }

    // looks like a text box; opens the ask view
    component AskField: Rectangle {
        objectName: "askField"
        Layout.fillWidth: true
        implicitHeight: 32
        radius: 16
        color: Qt.alpha(root.ui.text, af.hovered ? 0.09 : 0.05)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 14
            text: `Ask ${App.askLabel}…`
            color: root.ui.faint
            font.pixelSize: 13
        }
        HoverHandler { id: af; cursorShape: Qt.IBeamCursor }
        TapHandler { onTapped: root.expand("ask") }
    }

    QtObject {
        id: shimmer

        property real value: 1

        SequentialAnimation on value {
            // only while the island is open: an endless animation keeps the whole window redrawing
            running: root.mode === "expanded" && App.asking
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
                sub: App.usageLine

                TapHandler { onTapped: root.expand("limit") }
            }

            // every session of every agent; past four it scrolls
            Flickable {
                Layout.fillWidth: true
                implicitHeight: Math.min(rows.implicitHeight, 3 * 52 + 26)  // half a row peeks out: there is more
                contentHeight: rows.implicitHeight
                clip: contentHeight > height
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: rows

                    width: parent.width
                    spacing: 4

            Repeater {
                model: root.sessions

                Rectangle {
                    id: srow

                    required property var modelData

                    width: rows.width
                    implicitHeight: 48
                    radius: 12
                    color: Qt.alpha(root.ui.text, rh.hovered ? 0.07 : 0.035)

                    HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: App.focus(srow.modelData.sid) }

                    // a strip in the agent's colour says whose session this is
                    Rectangle {
                        x: 0
                        y: 10
                        width: 3
                        height: parent.height - 20
                        radius: 1.5
                        color: App.agentColour(srow.modelData.agent)
                    }

                    Column {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28

                        // project, then where it lives; agent and how long on the right
                        RowLayout {
                            width: parent.width
                            spacing: 6

                            Text {
                                text: srow.modelData.name
                                color: root.ui.text
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                // the name keeps its room; the path gives way first
                                Layout.preferredWidth: implicitWidth
                                Layout.minimumWidth: Math.min(implicitWidth, 90)
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.where(srow.modelData.cwd)
                                color: root.ui.faint
                                font.pixelSize: 12
                                elide: Text.ElideLeft
                            }
                            Text {
                                text: srow.modelData.agent ?? "claude"
                                color: App.agentColour(srow.modelData.agent)
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            Text {
                                visible: !!srow.modelData.started
                                text: root.age(srow.modelData.started)
                                color: root.ui.faint
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            width: parent.width
                            text: srow.modelData.state === "waiting" ? "Needs you" : root.plain(srow.modelData.ticker.slice(-1)[0]) || "Ready"
                            color: srow.modelData.state === "waiting" ? root.ui.accent : root.ui.dim
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
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
                    // a panel that hides itself takes no room
                    Layout.preferredHeight: item?.visible ? item.implicitHeight : -1
                    Layout.maximumHeight: item?.visible ? Infinity : 0
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

            Title {
                title: empty.connected ? "All quiet" : "Hi, I'm Emba"
                sub: empty.connected ? App.usageLine : ""

                HoverHandler { cursorShape: App.usageLine ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { onTapped: if (App.usageLine) root.expand("limit") }
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
                }
                Link {
                    text: "Terminal"
                    onClicked: App.focus(root.pending[0]?.sid ?? "")
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.min(code.implicitHeight, 110) + 18
                radius: 12
                color: root.ui.fill
                clip: true

                Text {
                    id: code

                    x: 10
                    y: 9
                    width: parent.width - 20
                    text: root.pending[0]?.full ?? ""
                    color: root.ui.text
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
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: parent.sess?.text ?? ""
                color: root.ui.dim
                font.pixelSize: 12
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            Flow {
                Layout.fillWidth: true
                spacing: 14

                Link {
                    text: "Open terminal"
                    onClicked: {
                        App.focus(root.finishedSid);
                        root.collapse();
                    }
                }
                Repeater {
                    model: App.actionsFor(root.finishedSid)

                    Link {
                        required property var modelData

                        text: modelData.label
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
                title: App.maxUsed >= App.cfg.limitWarn ? "Running low" : "Usage"
            }
            Dim {
                visible: !App.usageLine
                text: "Nothing to show yet. Claude shows up once its status line is connected (emba connect claude --statusline); Codex after its first reply."
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.rightMargin: 18
            }
            Repeater {
                // [label, { used, resets }] for every agent's windows
                model: [].concat(...Object.keys(App.limits).map(k => App.limits[k].windows.map(w => [`${k} · ${w.label.toLowerCase()} · ${w.used}%`, w])))

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
                        color: Qt.alpha(root.ui.text, 0.08)

                        Rectangle {
                            width: parent.width * Math.min(1, modelData[1].used / 100)
                            height: parent.height
                            radius: 3
                            color: modelData[1].used >= 90 ? root.ui.error : root.ui.accent
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
                        color: on ? root.ui.accent : Qt.alpha(root.ui.text, chipHover.hovered ? 0.1 : 0.05)

                        Behavior on color { ColorAnimation { duration: 140 } }

                        Text {
                            id: chip

                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.on ? root.ui.accentInk : root.ui.dim
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
                        color: Qt.alpha(root.ui.text, 0.08)

                        Text {
                            id: fname

                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, 184)
                            text: modelData.split(/[\\/]/).pop()
                            color: root.ui.dim
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
                color: root.ui.fill
                border.width: 1
                border.color: input.activeFocus ? Qt.alpha(root.ui.text, 0.2) : Qt.alpha(root.ui.text, 0.06)

                TextInput {
                    id: input

                    objectName: "askInput"

                    anchors.left: parent.left
                    anchors.right: tools.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 8
                    color: root.ui.text
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
                        text: micIcon.hovered ? micIcon.hint : areaIcon.hovered ? areaIcon.hint : root.files.length ? "What about it?" : `Ask ${App.askLabel}…`
                        color: root.ui.faint
                        font.pixelSize: 13
                    }
                }

                // talk, or point at something on screen
                Row {
                    id: tools

                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

ToolIcon {
                        id: micIcon
                        visible: !!App.cfg.voice
                        kind: "mic"
                        hint: "Talk to Emba"
                        onClicked: App.listen()
                    }
                    ToolIcon {
                        id: areaIcon
                        kind: "area"
                        hint: "Show Emba part of your screen"
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
                    color: App.askError ? root.ui.error : root.ui.text
                    font.pixelSize: 13
                    textFormat: TextEdit.MarkdownText
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 14

                Link {
                    visible: App.asking
                    text: "Stop"
                    onClicked: App.cancelAsk()
                }
                Link {
                    visible: !App.asking && !App.askError
                    text: "Copy"
                    onClicked: root.copy(App.answer)
                }
                Link {
                    visible: !App.asking && !App.askError
                    text: "Follow up"
                    onClicked: {
                        App.followUp = true;
                        root.files = [];
                        root.expand("ask");
                    }
                }
                Link {
                    visible: !App.asking && !App.askError && App.canContinue
                    text: "Continue in terminal"
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
            }
            AskField {}
            Link {
                text: "Copy path"
                onClicked: {
                    root.copy(root.files.join(" "));
                    root.collapse();
                }
            }
        }
    }

    Component {
        id: dropView

        // the whole card is the target; Emba leans in, mouth open
        Rectangle {
            implicitHeight: 96
            radius: 18
            color: Qt.alpha(root.ui.accent, 0.12)
            border.width: 2
            border.color: root.ui.accent

            Column {
                anchors.centerIn: parent
                spacing: 2

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Drop it here"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Dim {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Emba will ask about it"
                }
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
            }
            // no buttons and no instructions: rub, double-click, click, hold (see README)
            Dim {
                visible: Pet.napping
                text: "Click to wake"
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
                        color: root.ui.dim

                        Behavior on height { NumberAnimation { duration: 90 } }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 14
                visible: App.voiceState === ""

                Link {
                    text: "Try again"
                    onClicked: App.listen()
                }
                Link {
                    text: "Type instead"
                    onClicked: root.expand("ask")
                }
            }
        }
    }
}
