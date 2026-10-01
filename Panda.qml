import QtQuick
import qs

// Emba, the red panda: a little mochi-shaped creature drawn on a Canvas every frame.
//
// Set `mood` (what the session is doing) and optionally fire an emote; the
// frame loop below eases every pose value toward that mood's target, so any
// change of state blends instead of snapping.
Item {
    id: root

    // idle working thinking waiting question done error sleeping limit
    property string mood: "idle"
    // body colour; everything else is fixed so Emba always reads as Emba
    property color bodyColor: "#e2683c"
    property bool running: visible
    // gaze target in pixels relative to Emba's centre; null = wander
    property var gaze: null
    // 0..1 loudness while Emba speaks; opens the mouth in time with the voice
    property real talk: 0

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
            working: Theme.working,
            thinking: Theme.thinking,
            listening: Theme.working,
            waiting: Theme.warn,
            question: "#22d3ee",
            done: Theme.ok,
            error: Theme.error,
            sleeping: Theme.dim,
            limit: Theme.limit
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
        } else if (m === "listening") {
            // ears up, leaning in
            eyeScale = 1.15;
            lx = 0;
            ly = 0.25;
            arm = 0.3 + Math.sin(t * 3) * 0.08;
            bob = -1.5;
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
        p.mouth = Math.max(approach(p.mouth, mouth, 18, dt), Math.min(1, root.talk * 1.4));
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

    // a cursor resting on Emba for a while earns hearts
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

    // Built from points: Context2D.ellipse() mangles small ellipses (a 3x5
    // eye came out as a crescent), and Qt applies the transform at fill time,
    // so a scaled unit arc does not work either.
    function ellipse(c, x, y, rx, ry) {
        c.beginPath();
        for (let i = 0; i < 32; i++) {
            const a = i / 32 * Math.PI * 2;
            i === 0 ? c.moveTo(x + rx, y) : c.lineTo(x + rx * Math.cos(a), y + ry * Math.sin(a));
        }
        c.closePath();
    }

    // A rounded square: |x/rx|^n + |y/ry|^n = 1
    function squircle(c, x, y, rx, ry, n) {
        c.beginPath();
        for (let i = 0; i <= 48; i++) {
            const a = i / 48 * Math.PI * 2;
            const ca = Math.cos(a), sa = Math.sin(a);
            const px = x + rx * Math.sign(ca) * Math.pow(Math.abs(ca), 2 / n);
            const py = y + ry * Math.sign(sa) * Math.pow(Math.abs(sa), 2 / n);
            i === 0 ? c.moveTo(px, py) : c.lineTo(px, py);
        }
        c.closePath();
    }

    function draw(c, m, e) {
        const fur = root.bodyColor;
        const dark = "#3a2420";
        const cream = "#fff4e8";
        const ring = shade(fur, 0.68);

        // glow behind, in the mood colour
        if (p.glow > 0.01) {
            const g = c.createRadialGradient(0, 4, 8, 0, 4, 50);
            g.addColorStop(0, Qt.alpha(p.glowColor, p.glow * 0.55));
            g.addColorStop(1, Qt.alpha(p.glowColor, 0));
            c.fillStyle = g;
            ellipse(c, 0, 4, 50, 50);
            c.fill();
        }

        // ground shadow stays put while Emba hops
        c.fillStyle = "rgba(0,0,0,0.2)";
        const lift = Math.max(0, -p.bob) / 20;
        ellipse(c, 0, 38, 26 * (1 - lift * 0.4), 3.2 * (1 - lift * 0.4));
        c.fill();

        c.save();
        c.translate(0, p.bob);
        // squash about the base
        c.translate(0, 32);
        c.scale(1 + p.squash * 0.6, 1 - p.squash);
        c.translate(0, -32);
        c.rotate(p.roll + p.spin);

        // a short striped tail peeking out behind, wagging
        const wag = Math.sin(p.t * 2.2) * 4 + p.arm * 5;
        for (let i = 0; i <= 5; i++) {
            const k = i / 5;
            c.fillStyle = i % 2 === 1 ? ring : fur;
            ellipse(c, 27 + k * 13 + wag * k * 0.3, 20 - k * 16 + wag * k, 8 - k * 1.5, 8 - k * 1.5);
            c.fill();
        }

        // round ears, set behind the head
        const twitch = Math.max(0, Math.sin(p.t * 1.1) - 0.93) * 4;
        for (const sx of [-1, 1]) {
            c.save();
            c.translate(22 * sx, -19);
            c.rotate((0.25 + (sx > 0 ? twitch : 0)) * sx);
            c.fillStyle = fur;
            ellipse(c, 0, 0, 9, 9);
            c.fill();
            c.fillStyle = dark;
            ellipse(c, 0, -0.5, 4.8, 4.8);
            c.fill();
            c.restore();
        }

        // the body: one soft rounded square, that is all of it
        c.fillStyle = fur;
        squircle(c, 0, 4, 34, 28, 3);
        c.fill();
        c.save();
        squircle(c, 0, 4, 34, 28, 3);
        c.clip();
        c.fillStyle = "rgba(255,255,255,0.13)";
        ellipse(c, -6, -20, 30, 10);
        c.fill();
        c.restore();

        const fx = p.lookX * 6, fy = -p.lookY * 4;

        // red-panda brows: two cream dots
        c.fillStyle = cream;
        for (const sx of [-1, 1]) {
            ellipse(c, 10 * sx + fx, -8 + fy, 3.6, 2.6);
            c.fill();
        }

        // blush
        c.fillStyle = e === "love" ? "rgba(255,92,138,0.8)" : "rgba(255,150,170,0.55)";
        for (const sx of [-1, 1]) {
            ellipse(c, 19 * sx + fx, 11 + fy, 4.5, 2.8);
            c.fill();
        }

        for (const sx of [-1, 1])
            drawEye(c, 10 * sx + fx, 3 + fy, sx, m, e);

        // mouth only shows when it opens
        if (p.mouth > 0.08) {
            c.fillStyle = dark;
            ellipse(c, fx, 12 + fy, 2.2 + p.mouth * 1.5, 0.8 + p.mouth * 3);
            c.fill();
        }

        c.restore();

        // floating paws: not attached, they bob and wave on their own
        c.fillStyle = shade(fur, 0.78);
        for (const sx of [-1, 1]) {
            const lift = p.arm * (sx < 0 && p.waveLeft > 0 ? 22 : 14);
            ellipse(c, 41 * sx, 18 - lift + p.bob * 0.9 + Math.sin(p.t * 2 + sx) * 1.2, 5, 5);
            c.fill();
        }
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
        const rx = 3.3 * sc, ry = 4.8 * sc * open;
        ellipse(c, x, y, rx, ry);
        c.fill();
        // catchlights make it look alive
        c.fillStyle = "white";
        ellipse(c, x + 1 * sc, y - ry * 0.45, 1.1 * sc, 1.3 * sc * Math.min(1, open * 1.5));
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
