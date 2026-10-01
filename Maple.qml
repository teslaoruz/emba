import QtQuick

// Maple, perch's mascot: a red panda drawn on a Canvas every frame.
//
// Set `mood` (what the session is doing) and optionally fire an emote; the
// frame loop below eases every pose value toward that mood's target, so any
// change of state blends instead of snapping.
Item {
    id: root

    // idle working thinking waiting question done error sleeping limit
    property string mood: "idle"
    // body colour; everything else is fixed so Maple always reads as Maple
    property color bodyColor: "#d9622b"
    property bool running: visible
    // gaze target in pixels relative to Maple's centre; null = wander
    property var gaze: null

    signal clicked

    implicitWidth: 96
    implicitHeight: 96

    // ---- public reactions ----
    function boop() {
        p.squashVel += 9;
        emote("annoyed", 0.8);
    }
    function surprise() {
        p.bobVel -= 140;
        emote("surprised", 0.7);
    }
    function gulp() {
        p.mouthHold = 0.35;
        p.squashVel += 6;
        emote("happy", 1.2);
    }
    function wave() {
        p.waveLeft = 1.2;
        emote("happy", 1.2);
    }
    function dizzy() {
        emote("dizzy", 3.3);
    }
    function love() {
        emote("love", 2.2);
    }
    function emote(name, seconds) {
        p.emote = name;
        p.emoteLeft = seconds;
    }

    // ---- animation state, advanced once per frame ----
    QtObject {
        id: p

        property real t: 0
        // eased pose
        property real bob: 0
        property real bobVel: 0
        property real roll: 0
        property real squash: 0
        property real squashVel: 0
        property real arm: 0.1
        property real mouth: 0
        property real eyeOpen: 1
        property real eyeScale: 1
        property real lookX: 0
        property real lookY: 0
        property real spin: 0
        property real glow: 0
        property color glowColor: "transparent"
        // timers
        property real nextBlink: 2
        property real blinkLeft: 0
        property real wanderLeft: 1
        property point wander: Qt.point(0, 0)
        property real waveLeft: 0
        property real mouthHold: 0
        property string emote: ""
        property real emoteLeft: 0
        property real spinLeft: 0
        property real shakeLeft: 0
        property real particleLeft: 0
        property string lastMood: ""
    }

    readonly property var moodColours: ({
            idle: "#00000000",
            working: "#3b9eff",
            thinking: "#8b5cf6",
            waiting: "#f5a524",
            question: "#22d3ee",
            done: "#34d399",
            error: "#f4505e",
            sleeping: "#94a3b8",
            limit: "#fb923c"
        })

    function approach(cur, target, rate, dt) {
        return cur + (target - cur) * (1 - Math.exp(-rate * dt));
    }

    function step(dt) {
        p.t += dt;
        const t = p.t;
        const m = root.mood;

        if (m !== p.lastMood) {
            if (m === "done") {
                p.spinLeft = 0.95;
                p.bobVel -= 180;
            }
            if (m === "error")
                p.shakeLeft = 0.6;
            if (m === "waiting" || m === "question")
                p.bobVel -= 120;
            p.lastMood = m;
        }

        const e = p.emoteLeft > 0 ? p.emote : "";
        p.emoteLeft = Math.max(0, p.emoteLeft - dt);

        // targets for this mood
        let bob = 0, roll = 0, arm = 0.05, mouth = 0, eyeScale = 1, open = 1;
        let lx = p.wander.x, ly = p.wander.y;
        let breathe = 0.025 * Math.sin(t * 2.1);

        if (m === "working") {
            bob = -Math.abs(Math.sin(t * 7)) * 2.5;
            roll = Math.sin(t * 3.5) * 0.04;
            ly = -0.55;
            lx = Math.sin(t * 1.3) * 0.35;
            mouth = Math.max(0, Math.sin(t * 14)) * 0.35;
        } else if (m === "thinking") {
            lx = 0.6; ly = 0.7;
            roll = 0.08 + Math.sin(t * 1.5) * 0.03;
        } else if (m === "waiting" || m === "question") {
            const ph = (t * 0.9) % 1;
            bob = -Math.max(0, Math.sin(ph * Math.PI * 2)) * 7;
            arm = ph < 0.5 ? 0.5 + Math.sin(t * 30) * 0.25 : 0.15;
            eyeScale = 1.18;
            roll = m === "question" ? 0.17 : 0;
            lx = 0; ly = 0.1;
        } else if (m === "done") {
            arm = 0.9 + Math.sin(t * 22) * 0.35;
        } else if (m === "error") {
            arm = 0.05;
        } else if (m === "sleeping") {
            open = 0;
            roll = 0.13;
            arm = 0;
            breathe = 0.06 * Math.sin(t * 1.4);
            lx = 0; ly = -0.3;
        } else if (m === "limit") {
            open = 0.55;
            arm = 0.05;
            bob = 1.5;
        }

        // emotes win over the mood
        if (e === "surprised")
            eyeScale = 1.4;
        else if (e === "dizzy") {
            roll = Math.sin(t * 7) * 0.22;
            lx = Math.cos(t * 7) * 0.5;
            ly = Math.sin(t * 7) * 0.5;
        } else if (e === "love") {
            roll = Math.sin(t * 2.5) * 0.08;
            arm = 0.35;
        } else if (e === "annoyed")
            arm = 0.5;

        if (root.gaze && e !== "dizzy" && m !== "sleeping") {
            lx = Math.tanh(root.gaze.x / 260);
            ly = -Math.tanh(root.gaze.y / 200);
        }

        // blinking: random 2.2-5.4 s, sometimes twice
        p.nextBlink -= dt;
        if (p.nextBlink <= 0) {
            p.blinkLeft = 0.14;
            p.nextBlink = Math.random() < 0.22 ? 0.3 : 2.2 + Math.random() * 3.2;
        }
        if (p.blinkLeft > 0) {
            p.blinkLeft -= dt;
            open = Math.min(open, 0.08);
        }

        // looking around on its own when nothing holds its gaze
        p.wanderLeft -= dt;
        if (p.wanderLeft <= 0) {
            p.wander = Math.random() < 0.4 ? Qt.point(0, 0) : Qt.point(Math.random() * 1.6 - 0.8, Math.random() * 0.8 - 0.3);
            p.wanderLeft = 1.5 + Math.random() * 3;
        }

        if (p.waveLeft > 0) {
            p.waveLeft -= dt;
            arm = 0.7 + Math.sin(t * 24) * 0.45;
        }
        if (p.mouthHold > 0) {
            p.mouthHold -= dt;
            mouth = 1;
        }

        // springs for the bouncy bits, easing for the rest
        p.bobVel += (-260 * (p.bob - bob) - 14 * p.bobVel) * dt;
        p.bob += p.bobVel * dt;
        p.squashVel += (-320 * (p.squash - breathe) - 12 * p.squashVel) * dt;
        p.squash += p.squashVel * dt;
        p.roll = approach(p.roll, roll, 8, dt);
        p.arm = approach(p.arm, arm, 14, dt);
        p.mouth = approach(p.mouth, mouth, 18, dt);
        p.eyeScale = approach(p.eyeScale, eyeScale, 12, dt);
        p.eyeOpen = approach(p.eyeOpen, open, open < p.eyeOpen ? 40 : 18, dt);
        p.lookX = approach(p.lookX, lx, 7, dt);
        p.lookY = approach(p.lookY, ly, 7, dt);

        if (p.spinLeft > 0) {
            p.spinLeft = Math.max(0, p.spinLeft - dt);
            const k = 1 - p.spinLeft / 0.95;
            p.spin = Math.PI * 2 * (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2);
        } else
            p.spin = 0;
        if (p.shakeLeft > 0) {
            p.shakeLeft -= dt;
            p.roll += Math.sin(t * 46) * 0.2 * (p.shakeLeft / 0.6);
        }

        const g = moodColours[m] ?? "#00000000";
        p.glowColor = g;
        p.glow = approach(p.glow, m === "idle" ? 0 : 0.5 + 0.12 * Math.sin(t * 3), 5, dt);

        spawnParticles(m, e, dt);
        canvas.requestPaint();
    }

    // ---- particles: little glyphs that float off and die ----
    function spawnParticles(m, e, dt) {
        p.particleLeft -= dt;
        if (p.particleLeft > 0)
            return;
        let glyph = "", colour = "", every = 0;
        if (e === "love") {
            glyph = "♥"; colour = "#ff5c8a"; every = 0.28;
        } else if (e === "dizzy") {
            glyph = "✦"; colour = "#ffd166"; every = 0.22;
        } else if (e === "annoyed") {
            glyph = "#"; colour = "#a855f7"; every = 0.5;
        } else if (m === "done") {
            glyph = "✦"; colour = Math.random() < 0.5 ? "#ffd166" : "#34d399"; every = 0.12;
        } else if (m === "sleeping") {
            glyph = "z"; colour = "#94a3b8"; every = 1.3;
        } else if (m === "limit") {
            glyph = "●"; colour = "#7cc7ff"; every = 1.1;
        }
        p.particleLeft = every || 0.2;
        if (!glyph)
            return;
        const s = root.width / 100;
        const sweat = glyph === "●";
        particle.createObject(fx, {
            text: glyph,
            color: colour,
            x: root.width / 2 + (sweat ? 30 * s : (Math.random() * 60 - 30) * s),
            y: root.height / 2 - (sweat ? 10 : 20) * s,
            dx: sweat ? 4 * s : (Math.random() * 30 - 15) * s,
            dy: sweat ? 26 * s : -(38 + Math.random() * 20) * s,
            px: (glyph === "z" ? 13 : sweat ? 6 : 11) * s
        });
    }

    Component {
        id: particle

        Text {
            id: pt

            property real dx
            property real dy
            property real px

            font.pixelSize: px
            font.bold: true
            opacity: 0

            ParallelAnimation {
                running: true
                onFinished: pt.destroy()

                NumberAnimation { target: pt; property: "x"; to: pt.x + pt.dx; duration: 1100; easing.type: Easing.OutQuad }
                NumberAnimation { target: pt; property: "y"; to: pt.y + pt.dy; duration: 1100; easing.type: Easing.OutQuad }
                NumberAnimation { target: pt; property: "scale"; from: 0.4; to: 1.2; duration: 1100 }
                SequentialAnimation {
                    NumberAnimation { target: pt; property: "opacity"; to: 1; duration: 150 }
                    PauseAnimation { duration: 600 }
                    NumberAnimation { target: pt; property: "opacity"; to: 0; duration: 350 }
                }
            }
        }
    }

    FrameAnimation {
        running: root.running
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    // ---- drawing, in a 100x100 box centred on the body ----
    Canvas {
        id: canvas

        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const s = width / 100;
            c.scale(s, s);
            c.translate(50, 52);
            root.draw(c, root.mood, p.emoteLeft > 0 ? p.emote : "");
        }
    }

    Item {
        id: fx

        anchors.fill: parent
    }

    // speech badge above the head for states that want attention
    Rectangle {
        readonly property string glyph: root.mood === "waiting" ? "!" : root.mood === "question" ? "?" : root.mood === "thinking" ? "…" : ""

        visible: glyph !== ""
        x: root.width * 0.66
        y: root.height * 0.02 + p.bob * root.width / 100 + Math.sin(p.t * 4) * 2
        width: root.width * 0.24
        height: width
        radius: width / 2
        color: root.moodColours[root.mood] ?? "#f5a524"
        scale: visible ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: "white"
            font.pixelSize: parent.width * 0.7
            font.bold: true
        }
    }

    HoverHandler {
        id: hover

        onHoveredChanged: {
            if (hovered) {
                p.blinkLeft = 0.14;
                dwell.restart();
            } else
                dwell.stop();
        }
    }

    // a cursor resting on Maple for a while earns hearts
    Timer {
        id: dwell

        interval: 1900
        onTriggered: root.love()
    }

    TapHandler {
        property var taps: []

        onTapped: {
            const now = Date.now();
            taps = taps.filter(x => now - x < 1700).concat([now]);
            if (taps.length >= 3) {
                taps = [];
                root.dizzy();
            }
            root.clicked();
        }
    }

    function shade(col, k) {
        return Qt.rgba(col.r * k, col.g * k, col.b * k, 1);
    }

    function ellipse(c, x, y, rx, ry) {
        c.beginPath();
        c.ellipse(x - rx, y - ry, rx * 2, ry * 2);
    }

    function draw(c, m, e) {
        const fur = root.bodyColor;
        const dark = "#3d2420";
        const cream = "#fff6ec";
        const mark = shade(fur, 0.7);

        // glow behind, in the mood colour
        if (p.glow > 0.01) {
            c.globalAlpha = p.glow * 0.35;
            c.fillStyle = p.glowColor;
            ellipse(c, 0, 4, 47, 45);
            c.fill();
            c.globalAlpha = 1;
        }

        // ground shadow stays put while Maple hops
        c.fillStyle = "rgba(0,0,0,0.18)";
        const lift = Math.max(0, -p.bob) / 20;
        ellipse(c, 0, 44, 26 * (1 - lift * 0.4), 3.5 * (1 - lift * 0.4));
        c.fill();

        c.save();
        c.translate(0, p.bob);
        // squash about the feet
        c.translate(0, 42);
        c.scale(1 + p.squash * 0.6, 1 - p.squash);
        c.translate(0, -42);
        c.rotate(p.roll + p.spin);

        // striped tail curling up behind, swaying on its own
        // Built from overlapping discs along a curve; every other band is dark,
        // and the tip is dark too, like the real thing.
        const sway = Math.sin(p.t * 1.8) * 5 + p.arm * 4;
        for (let i = 0; i <= 22; i++) {
            const k = i / 22;
            const tx = 14 + 26 * Math.sin(k * 1.5) + sway * k * k;
            const ty = 38 - 44 * k + 7 * Math.sin(k * 3.1);
            c.fillStyle = k > 0.88 || Math.floor(k * 7) % 2 === 1 ? mark : fur;
            const r = 7.5 + 2.5 * Math.sin(k * Math.PI) - k * 2;
            ellipse(c, tx, ty, r, r);
            c.fill();
        }

        // legs
        c.fillStyle = dark;
        for (const sx of [-1, 1]) {
            ellipse(c, 9 * sx, 40, 6.5, 4.5);
            c.fill();
        }

        // body: rusty back, dark chest
        c.fillStyle = fur;
        ellipse(c, 0, 28, 20, 15);
        c.fill();
        c.fillStyle = dark;
        ellipse(c, 0, 31, 12, 11);
        c.fill();

        // arms, hinged at the shoulders: they rise to wave and cheer
        c.fillStyle = dark;
        for (const sx of [-1, 1]) {
            c.save();
            c.translate(15 * sx, 21);
            c.rotate(-p.arm * 1.6 * sx);
            ellipse(c, 0, 8, 5, 9.5);
            c.fill();
            c.restore();
        }

        // ears twitch now and then
        const twitch = Math.max(0, Math.sin(p.t * 1.1) - 0.93) * 4;
        for (const sx of [-1, 1]) {
            c.save();
            c.translate(23 * sx, -22);
            c.rotate((0.35 + (sx > 0 ? twitch : 0)) * sx);
            c.fillStyle = cream;
            ellipse(c, 0, -5, 10, 11);
            c.fill();
            c.fillStyle = fur;
            ellipse(c, 0, -4, 8.5, 9.5);
            c.fill();
            c.fillStyle = dark;
            ellipse(c, 0, -2.5, 5, 6);
            c.fill();
            c.restore();
        }

        // head
        c.fillStyle = fur;
        ellipse(c, 0, -2, 33, 27);
        c.fill();

        // the face shifts a little toward the gaze, so the head seems to turn
        const fx = p.lookX * 4, fy = -p.lookY * 2.5;

        // white mask: cheek patches, brows, muzzle
        c.save();
        ellipse(c, 0, -2, 33, 27);
        c.clip();
        c.fillStyle = cream;
        for (const sx of [-1, 1]) {
            ellipse(c, 25 * sx + fx * 0.6, 8 + fy, 11, 10);
            c.fill();
            ellipse(c, 12 * sx + fx, -15 + fy, 5, 3.4);
            c.fill();
        }
        ellipse(c, fx, 10 + fy, 13, 9.5);
        c.fill();
        // tear marks running from each eye down to the muzzle
        c.fillStyle = mark;
        for (const sx of [-1, 1]) {
            c.save();
            c.translate(14.5 * sx + fx, 8 + fy);
            c.rotate(-0.35 * sx);
            ellipse(c, 0, 0, 3.6, 8);
            c.fill();
            c.restore();
        }
        // soft highlight on the crown
        c.fillStyle = "rgba(255,255,255,0.16)";
        ellipse(c, -9, -21, 15, 6);
        c.fill();
        c.restore();

        // blush
        c.fillStyle = e === "love" ? "rgba(255,92,138,0.8)" : "rgba(255,120,150,0.55)";
        for (const sx of [-1, 1]) {
            ellipse(c, 21 * sx + fx, 9 + fy, 4.5, 3);
            c.fill();
        }

        for (const sx of [-1, 1])
            drawEye(c, 12 * sx + fx * 1.4, -4 + fy * 1.5, sx, m, e);

        // nose and mouth
        const nx = fx * 1.2, ny = 5 + fy;
        c.fillStyle = dark;
        c.beginPath();
        c.moveTo(nx - 3.6, ny - 1.5);
        c.lineTo(nx + 3.6, ny - 1.5);
        c.lineTo(nx, ny + 2);
        c.closePath();
        c.fill();
        if (p.mouth > 0.08) {
            c.fillStyle = "#7a2a2a";
            ellipse(c, nx, ny + 5.5, 3 + p.mouth, 1 + p.mouth * 3);
            c.fill();
            c.fillStyle = "#ff8a9a";
            ellipse(c, nx, ny + 6 + p.mouth * 1.6, 2 + p.mouth * 0.6, p.mouth * 1.4);
            c.fill();
        } else {
            // the little "ω"
            c.strokeStyle = dark;
            c.lineWidth = 1.4;
            c.lineCap = "round";
            c.beginPath();
            c.arc(nx - 2.2, ny + 3, 2.2, 0.1 * Math.PI, 0.95 * Math.PI);
            c.moveTo(nx + 4.4, ny + 3.3);
            c.arc(nx + 2.2, ny + 3, 2.2, 0.05 * Math.PI, 0.9 * Math.PI);
            c.stroke();
        }

        c.restore();
    }

    function drawEye(c, x, y, sx, m, e) {
        const ink = "#1e1a24";
        const sc = p.eyeScale;
        c.fillStyle = ink;
        c.strokeStyle = ink;
        c.lineCap = "round";
        c.lineWidth = 2.6;

        if (e === "love") {
            c.fillStyle = "#ff3f73";
            const r = 3.6 * sc;
            c.beginPath();
            c.moveTo(x, y + r * 1.3);
            c.bezierCurveTo(x - r * 2.2, y - r * 0.2, x - r * 0.9, y - r * 1.9, x, y - r * 0.6);
            c.bezierCurveTo(x + r * 0.9, y - r * 1.9, x + r * 2.2, y - r * 0.2, x, y + r * 1.3);
            c.fill();
            return;
        }
        if (e === "dizzy") {
            c.lineWidth = 1.8;
            c.beginPath();
            for (let a = 0; a < Math.PI * 5; a += 0.3) {
                const r = a * 0.42;
                const px = x + Math.cos(a + p.t * 9 * sx) * r, py = y + Math.sin(a + p.t * 9 * sx) * r;
                a === 0 ? c.moveTo(px, py) : c.lineTo(px, py);
            }
            c.stroke();
            return;
        }
        if (m === "error" && !e) {
            const r = 3.4;
            c.beginPath();
            c.moveTo(x - r, y - r); c.lineTo(x + r, y + r);
            c.moveTo(x + r, y - r); c.lineTo(x - r, y + r);
            c.stroke();
            return;
        }
        if (e === "happy" || (m === "done" && !e)) {
            c.beginPath();
            c.arc(x, y + 2, 4.2, Math.PI * 1.15, Math.PI * 1.85);
            c.stroke();
            return;
        }
        if (e === "annoyed") {
            c.beginPath();
            c.moveTo(x - 4 * sx, y - 3);
            c.lineTo(x + 3.5 * sx, y);
            c.lineTo(x - 4 * sx, y + 3);
            c.stroke();
            return;
        }

        const open = p.eyeOpen;
        if (open < 0.15) {
            // shut: a soft downward curve
            c.beginPath();
            c.arc(x, y - 1, 4, Math.PI * 0.15, Math.PI * 0.85);
            c.stroke();
            return;
        }
        const rx = 4.8 * sc, ry = 6.2 * sc * open;
        ellipse(c, x, y, rx, ry);
        c.fill();
        // catchlights make it look alive
        c.fillStyle = "white";
        ellipse(c, x + 1.7 * sc, y - ry * 0.4, 1.9 * sc, 2.1 * sc * Math.min(1, open * 1.5));
        c.fill();
        if (sc > 1.1) {
            ellipse(c, x - 1.2 * sc, y + ry * 0.4, 0.7 * sc, 0.7 * sc);
            c.fill();
        }
        // tired: a flat lid across the top
        if (m === "limit" && !e) {
            c.fillStyle = root.bodyColor;
            c.fillRect(x - rx - 1, y - ry - 1, rx * 2 + 2, ry * 0.9);
        }
    }
}
