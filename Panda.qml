import QtQuick
import qs

// Emba, the red panda: a soft little mochi-shaped creature, drawn on a Canvas
// every frame.
//
// Set `mood` (what is going on) and Emba acts it out: it types on a tiny
// laptop while an agent works, taps its chin while thinking, jumps and waves
// when it needs you, dances when work is done. In between it has a life of
// its own: little dances, hops, stretches, spins, sneezes. Every pose value
// eases or springs toward its target, so nothing ever snaps.
Item {
    id: root

    // idle working thinking listening waiting question done error sleeping
    // limit hungry sleepy lonely
    property string mood: "idle"
    property color bodyColor: "#e2683c"
    property bool running: visible
    // gaze target in pixels relative to Emba's centre; null = look around
    property var gaze: null
    // 0..1 loudness while Emba speaks; opens the mouth in time with the voice
    property real talk: 0
    // something tasty is being dragged closer
    property bool eager: false
    // left alone for a while, Emba entertains itself
    property bool lively: true

    signal clicked
    signal petted
    signal doubleClicked
    signal held

    implicitWidth: 96
    implicitHeight: 96

    // grows a little, springily, when you point at it
    scale: hover.hovered ? 1.08 : 1
    Behavior on scale {
        SpringAnimation {
            spring: 5
            damping: 0.22
        }
    }

    // ---- reactions anyone can trigger ----
    function boop() {
        p.syVel -= 2.2;
        p.sxVel += 1.6;
        const r = ["giggle", "surprised", "spin", "annoyed"][Math.floor(Math.random() * 4)];
        if (r === "spin")
            act("spin");
        else
            emote(r === "giggle" ? "happy" : r, 0.9);
    }
    function surprise() {
        hop(1);
        emote("surprised", 0.7);
    }
    function gulp() {
        p.mouthHold = 0.35;
        p.syVel -= 1.4;
        emote("happy", 1.2);
    }
    function wave() {
        act("wave");
        emote("happy", 1.4);
    }
    function dizzy() {
        emote("dizzy", 3.3);
    }
    function love() {
        emote("love", 2.2);
        p.purr = 1.4;
    }
    function shakeHead() {
        p.shakeLeft = 0.6;
    }
    function emote(name, seconds) {
        p.emote = name;
        p.emoteLeft = seconds;
    }
    // a short routine: dance spin hop stretch wave lookaround tailchase sneeze
    function act(name) {
        p.act = name;
        p.actT = 0;
        p.actLen = ({
                dance: 2.6,
                spin: 0.9,
                hop: 0.7,
                stretch: 2.0,
                wave: 1.3,
                lookaround: 2.4,
                tailchase: 1.8,
                sneeze: 1.4
            })[name] ?? 1;
        if (name === "spin")
            p.spinLeft = 0.9;
        if (name === "hop")
            hop(1);
    }
    function hop(strength) {
        p.bobVel -= 150 * strength;
        p.syVel += 1.8 * strength;   // stretch on the way up
        p.sxVel -= 1.2 * strength;
    }

    // ---- animation state, advanced once per frame ----
    QtObject {
        id: p

        property real t: 0
        // body position and shape (springs)
        property real bob: 0
        property real bobVel: 0
        property real sway: 0
        property real sx: 1
        property real sxVel: 0
        property real sy: 1
        property real syVel: 0
        property real roll: 0
        property real spin: 0
        // limbs and face (eased)
        property real armL: 0
        property real armR: 0
        property real pawSpread: 0
        property real mouth: 0
        property real eyeOpen: 1
        property real eyeScale: 1
        property real lookX: 0
        property real lookY: 0
        property real earL: 0
        property real earR: 0
        property real tail: 0
        property real tailVel: 0
        property real glow: 0
        property color glowColor: "transparent"
        property real laptop: 0
        // timers
        property real nextBlink: 2
        property real blinkLeft: 0
        property real wanderLeft: 1
        property point wander: Qt.point(0, 0)
        property real mouthHold: 0
        property string emote: ""
        property real emoteLeft: 0
        property real spinLeft: 0
        property real shakeLeft: 0
        property real purr: 0
        property real particleLeft: 0
        property string lastMood: ""
        property string act: ""
        property real actT: 0
        property real actLen: 0
        property real nextAct: 5
        property real noteLeft: 0
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
    function ease(k) {
        return k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
    }

    function step(dt) {
        p.t += dt;
        const t = p.t;
        const m = root.mood;

        if (m !== p.lastMood) {
            if (m === "done")
                act("dance");
            if (m === "error")
                p.shakeLeft = 0.6;
            if (m === "waiting" || m === "question")
                hop(0.8);
            if (m === "listening")
                hop(0.4);
            p.lastMood = m;
        }

        const e = p.emoteLeft > 0 ? p.emote : "";
        p.emoteLeft = Math.max(0, p.emoteLeft - dt);

        // ---- targets for this mood ----
        let bob = 0, sway = 0, roll = 0, armL = 0.05, armR = 0.05, spread = 0, mouth = 0, eyeScale = 1, open = 1;
        let lx = p.wander.x, ly = p.wander.y, laptop = 0, earL = 0, earR = 0, tail = Math.sin(t * 1.6) * 0.25;
        let sx = 1 + 0.018 * Math.sin(t * 2.1), sy = 1 - 0.018 * Math.sin(t * 2.1);  // breathing

        if (m === "working") {
            // typing away on a tiny laptop, paws alternating
            laptop = 1;
            ly = -0.55;
            lx = Math.sin(t * 0.9) * 0.25;
            armL = 0.25 + Math.max(0, Math.sin(t * 13)) * 0.22;
            armR = 0.25 + Math.max(0, Math.sin(t * 13 + Math.PI)) * 0.22;
            spread = -0.45;
            bob = -Math.abs(Math.sin(t * 6.5)) * 1.2;
            roll = Math.sin(t * 1.3) * 0.03;
            tail = Math.sin(t * 3) * 0.35;
        } else if (m === "thinking") {
            // paw on chin, eyes up, head tilting
            lx = 0.55; ly = 0.75;
            armR = 0.95;
            spread = -0.85;
            roll = 0.1 + Math.sin(t * 1.2) * 0.05;
            earL = Math.sin(t * 2) * 0.1;
        } else if (m === "listening") {
            // a paw cupped to the ear, leaning in
            armL = 1.25;
            spread = -0.2;
            roll = -0.12;
            lx = -0.2; ly = 0.15;
            eyeScale = 1.12;
            earL = -0.35;
            sx *= 1.04; sy *= 1.04;
        } else if (m === "waiting" || m === "question") {
            // bouncing and waving both paws
            const ph = (t * 1.1) % 1;
            bob = -Math.max(0, Math.sin(ph * Math.PI * 2)) * 6;
            armL = 0.9 + Math.sin(t * 16) * 0.3;
            armR = 0.9 + Math.sin(t * 16 + 1.2) * 0.3;
            eyeScale = 1.18;
            roll = m === "question" ? 0.17 : Math.sin(t * 4) * 0.05;
            lx = 0; ly = 0.1;
            earL = earR = 0.2 * Math.sin(t * 10);
        } else if (m === "done") {
            armL = armR = 1.1;
        } else if (m === "error") {
            armL = armR = 0;
            sy *= 0.96;
        } else if (m === "sleeping") {
            open = 0;
            roll = 0.16;
            armL = armR = 0;
            sx = 1 + 0.04 * Math.sin(t * 1.3);
            sy = 0.94 - 0.04 * Math.sin(t * 1.3);
            lx = 0; ly = -0.3;
            earL = earR = -0.25;
            tail = 0.6;
        } else if (m === "limit") {
            open = 0.55;
            bob = 1.5;
            sy *= 0.95;
        } else if (m === "hungry") {
            open = 0.8;
            ly = -0.35;
            const rumble = (t % 4) < 0.5;
            roll = rumble ? Math.sin(t * 40) * 0.05 : 0;
            mouth = rumble ? 0.25 : 0;
            armL = armR = rumble ? 0.35 : 0.05;   // paws on tummy
            spread = rumble ? -0.9 : 0;
            sy *= 0.97;
        } else if (m === "sleepy") {
            const yawn = (t % 7) < 1.3;
            open = yawn ? 0 : 0.45;
            mouth = yawn ? Math.sin((t % 7) / 1.3 * Math.PI) : 0;
            armL = armR = yawn ? 1.0 : 0.02;
            if (yawn) {
                sy *= 1.06;
                sx *= 0.96;
            }
            earL = earR = -0.2;
        } else if (m === "lonely") {
            eyeScale = 1.15;
            armL = 0.15 + Math.max(0, Math.sin(t * 1.3)) * 0.35;
            bob = 1;
            sy *= 0.97;
            earL = earR = -0.15;
        }

        // ---- a life of its own when nothing is going on ----
        const calm = (m === "idle" || m === "lonely") && !e && !root.eager && !root.gaze;
        if (root.lively && calm && !p.act) {
            p.nextAct -= dt;
            if (p.nextAct <= 0) {
                const pool = ["dance", "hop", "stretch", "lookaround", "wave", "tailchase", "spin", "sneeze", "hop", "lookaround"];
                act(pool[Math.floor(Math.random() * pool.length)]);
                p.nextAct = 4 + Math.random() * 7;
            }
        }

        if (p.act) {
            p.actT += dt;
            const k = Math.min(1, p.actT / p.actLen);
            const a = p.act;
            if (a === "dance") {
                // side to side to a beat, paws up in turn, little hops
                const beat = t * 5.2;
                sway = Math.sin(beat) * 9;
                roll = Math.sin(beat) * 0.16;
                bob = -Math.abs(Math.sin(beat)) * 5;
                armL = 0.9 + Math.sin(beat) * 0.5;
                armR = 0.9 - Math.sin(beat) * 0.5;
                sx = 1 + Math.abs(Math.cos(beat)) * 0.06;
                sy = 1 - Math.abs(Math.cos(beat)) * 0.06;
                tail = Math.sin(beat * 2) * 0.8;
                earL = Math.sin(beat) * 0.3;
                earR = -earL;
                open = 1;
                eyeScale = 1;
                p.noteLeft -= dt;
                if (p.noteLeft <= 0) {
                    burst("♪", Theme.thinking, 1);
                    p.noteLeft = 0.4;
                }
            } else if (a === "stretch") {
                // up on tiptoe, paws high, then a big yawn
                const up = Math.sin(k * Math.PI);
                sy = 1 + up * 0.14;
                sx = 1 - up * 0.08;
                armL = armR = up * 1.4;
                spread = up * 0.4;
                open = k > 0.35 && k < 0.75 ? 0 : 1;
                mouth = k > 0.35 && k < 0.75 ? Math.sin((k - 0.35) / 0.4 * Math.PI) : 0;
            } else if (a === "lookaround") {
                lx = k < 0.33 ? -0.9 : k < 0.66 ? 0.9 : 0;
                ly = 0.15;
                roll = lx * -0.1;
                earL = lx > 0 ? 0.3 : 0;
                earR = lx < 0 ? 0.3 : 0;
            } else if (a === "wave") {
                armR = 1.2 + Math.sin(t * 22) * 0.35;
                roll = -0.06;
                lx = 0; ly = 0;
            } else if (a === "tailchase") {
                // turns to look at its own tail, tail flicks away
                lx = 1; ly = -0.4;
                roll = 0.2 * Math.sin(k * Math.PI);
                tail = Math.sin(t * 14) * 1.2;
                sway = Math.sin(k * Math.PI) * 6;
            } else if (a === "sneeze") {
                // ah... ah... choo!
                if (k < 0.6) {
                    sy = 1 + k * 0.15;
                    open = 1 - k;
                    roll = -k * 0.15;
                    mouth = k * 0.6;
                } else if (p.actT - dt < p.actLen * 0.6) {
                    p.syVel -= 3;
                    p.sxVel += 2;
                    burst("✦", "#ffffff", 3);
                } else {
                    open = 0;
                }
            }
            if (p.actT >= p.actLen)
                p.act = "";
        }

        // ---- emotes win over everything ----
        if (e === "surprised") {
            eyeScale = 1.4;
            earL = earR = 0.35;
        } else if (e === "dizzy") {
            roll = Math.sin(t * 7) * 0.22;
            lx = Math.cos(t * 7) * 0.5;
            ly = Math.sin(t * 7) * 0.5;
        } else if (e === "love") {
            roll = Math.sin(t * 2.5) * 0.08;
            armL = armR = 0.6;
            spread = -0.7;   // paws to cheeks
        } else if (e === "annoyed") {
            armL = armR = 0.45;
            sy *= 0.95;
        } else if (e === "happy") {
            armL = armR = Math.max(armL, 0.5);
        }

        if (root.eager) {
            mouth = 0.85;
            eyeScale = Math.max(eyeScale, 1.2);
            armL = armR = 0.6 + Math.sin(t * 9) * 0.15;
            spread = 0.3;
            sx *= 1.03; sy *= 1.03;
        }
        if (p.mouthHold > 0) {
            p.mouthHold -= dt;
            mouth = 1;
        }

        // the cursor holds the eyes; Emba leans and perks its ears toward it
        if (root.gaze && e !== "dizzy" && m !== "sleeping") {
            lx = Math.tanh(root.gaze.x / 260);
            ly = -Math.tanh(root.gaze.y / 200);
            const near = Math.max(0, 1 - Math.hypot(root.gaze.x, root.gaze.y) / 260);
            sway += lx * 4 * near;
            roll += lx * 0.08 * near;
            earL = Math.max(earL, 0.25 * near);
            earR = Math.max(earR, 0.25 * near);
        }

        // purring after petting: a tiny happy vibration
        if (p.purr > 0) {
            p.purr -= dt;
            sway += Math.sin(t * 60) * 0.6;
            open = Math.min(open, 0.12);
        }

        // blinking: random 2.2-5.4 s, sometimes twice
        p.nextBlink -= dt;
        if (p.nextBlink <= 0) {
            p.blinkLeft = 0.13;
            p.nextBlink = Math.random() < 0.22 ? 0.28 : 2.2 + Math.random() * 3.2;
        }
        if (p.blinkLeft > 0) {
            p.blinkLeft -= dt;
            open = Math.min(open, 0.06);
        }

        // looking around on its own
        p.wanderLeft -= dt;
        if (p.wanderLeft <= 0) {
            p.wander = Math.random() < 0.4 ? Qt.point(0, 0) : Qt.point(Math.random() * 1.6 - 0.8, Math.random() * 0.8 - 0.3);
            p.wanderLeft = 1.5 + Math.random() * 3;
        }

        // ---- integrate: springs for the bouncy bits, easing for the rest ----
        p.bobVel += (-260 * (p.bob - bob) - 13 * p.bobVel) * dt;
        p.bob += p.bobVel * dt;
        p.sxVel += (-300 * (p.sx - sx) - 11 * p.sxVel) * dt;
        p.sx += p.sxVel * dt;
        p.syVel += (-300 * (p.sy - sy) - 11 * p.syVel) * dt;
        p.sy += p.syVel * dt;
        // landing from a hop squashes
        if (p.bob > -0.5 && p.bobVel > 60) {
            p.syVel -= p.bobVel * 0.012;
            p.sxVel += p.bobVel * 0.008;
        }
        p.tailVel += (-60 * (p.tail - tail) - 6 * p.tailVel) * dt;  // a lazy, swishy spring
        p.tail += p.tailVel * dt;
        p.sway = approach(p.sway, sway, 9, dt);
        p.roll = approach(p.roll, roll, 9, dt);
        p.armL = approach(p.armL, armL, 15, dt);
        p.armR = approach(p.armR, armR, 15, dt);
        p.pawSpread = approach(p.pawSpread, spread, 12, dt);
        p.mouth = Math.max(approach(p.mouth, mouth, 18, dt), Math.min(1, root.talk * 1.4));
        p.eyeScale = approach(p.eyeScale, eyeScale, 12, dt);
        p.eyeOpen = approach(p.eyeOpen, open, open < p.eyeOpen ? 40 : 18, dt);
        p.lookX = approach(p.lookX, lx, 7, dt);
        p.lookY = approach(p.lookY, ly, 7, dt);
        p.laptop = approach(p.laptop, laptop, 8, dt);
        // ears: own twitches on top of whatever the pose wants
        const twitchL = Math.max(0, Math.sin(t * 1.1) - 0.94) * 5;
        const twitchR = Math.max(0, Math.sin(t * 0.83 + 2) - 0.94) * 5;
        p.earL = approach(p.earL, earL + twitchL, 14, dt);
        p.earR = approach(p.earR, earR + twitchR, 14, dt);

        if (p.spinLeft > 0) {
            p.spinLeft = Math.max(0, p.spinLeft - dt);
            p.spin = Math.PI * 2 * ease(1 - p.spinLeft / 0.9);
            if (p.spinLeft === 0)
                p.spin = 0;
        }
        if (p.shakeLeft > 0) {
            p.shakeLeft -= dt;
            p.roll += Math.sin(t * 46) * 0.2 * (p.shakeLeft / 0.6);
        }

        p.glowColor = moodColours[m] ?? "#00000000";
        p.glow = approach(p.glow, (m === "idle" || !moodColours[m]) ? 0 : 0.5 + 0.12 * Math.sin(t * 3), 5, dt);

        spawnParticles(m, e, dt);
        canvas.requestPaint();
    }

    // ---- particles: little things that float off and fade ----
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
            confetti();
            every = 0.09;
        } else if (m === "sleeping") {
            glyph = "z"; colour = "#94a3b8"; every = 1.3;
        } else if (m === "limit") {
            glyph = "●"; colour = "#7cc7ff"; every = 1.1;
        } else if (m === "hungry") {
            glyph = "…"; colour = "#c9a27e"; every = 3;
        } else if (m === "lonely") {
            glyph = "♡"; colour = "#ff9db5"; every = 3.5;
        }
        p.particleLeft = every || 0.2;
        if (glyph)
            burst(glyph, colour, 1);
    }

    function burst(glyph, colour, n) {
        const s = root.width / 100;
        for (let i = 0; i < n; i++) {
            const sweat = glyph === "●";
            particle.createObject(fx, {
                text: glyph,
                color: colour,
                x: root.width / 2 + (sweat ? 30 * s : (Math.random() * 60 - 30) * s),
                y: root.height / 2 - (sweat ? 10 : 22) * s,
                dx: sweat ? 4 * s : (Math.random() * 34 - 17) * s,
                dy: sweat ? 26 * s : -(36 + Math.random() * 22) * s,
                px: (glyph === "z" ? 13 : sweat ? 6 : glyph === "♪" ? 14 : 11) * s
            });
        }
    }

    // a celebration: colourful bits that pop up and flutter down
    function confetti() {
        const s = root.width / 100;
        const colours = ["#ffd166", "#34d399", "#60a5fa", "#f472b6", "#a78bfa", "#fb923c"];
        bit.createObject(fx, {
            color: colours[Math.floor(Math.random() * colours.length)],
            x: root.width / 2 + (Math.random() * 50 - 25) * s,
            y: root.height / 2 - 10 * s,
            dx: (Math.random() * 70 - 35) * s,
            up: (30 + Math.random() * 25) * s,
            fall: (40 + Math.random() * 20) * s,
            width: (2 + Math.random() * 2) * s,
            height: (3 + Math.random() * 3) * s
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

                NumberAnimation { target: pt; property: "x"; to: pt.x + pt.dx; duration: 1200; easing.type: Easing.OutQuad }
                NumberAnimation { target: pt; property: "y"; to: pt.y + pt.dy; duration: 1200; easing.type: Easing.OutQuad }
                NumberAnimation { target: pt; property: "scale"; from: 0.4; to: 1.2; duration: 1200; easing.type: Easing.OutBack }
                NumberAnimation { target: pt; property: "rotation"; from: -15; to: 15; duration: 1200 }
                SequentialAnimation {
                    NumberAnimation { target: pt; property: "opacity"; to: 1; duration: 150 }
                    PauseAnimation { duration: 650 }
                    NumberAnimation { target: pt; property: "opacity"; to: 0; duration: 400 }
                }
            }
        }
    }

    Component {
        id: bit

        Rectangle {
            id: cb

            property real dx
            property real up
            property real fall

            radius: 1
            antialiasing: true

            SequentialAnimation {
                running: true
                onFinished: cb.destroy()

                ParallelAnimation {
                    NumberAnimation { target: cb; property: "y"; to: cb.y - cb.up; duration: 420; easing.type: Easing.OutQuad }
                    NumberAnimation { target: cb; property: "x"; to: cb.x + cb.dx * 0.5; duration: 420 }
                }
                ParallelAnimation {
                    NumberAnimation { target: cb; property: "y"; to: cb.y - cb.up + cb.fall; duration: 900; easing.type: Easing.InQuad }
                    NumberAnimation { target: cb; property: "x"; to: cb.x + cb.dx; duration: 900 }
                    NumberAnimation { target: cb; property: "rotation"; from: 0; to: 540; duration: 900 }
                    NumberAnimation { target: cb; property: "opacity"; from: 1; to: 0; duration: 900; easing.type: Easing.InQuad }
                }
            }
        }
    }

    FrameAnimation {
        running: root.running
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    // ---- drawing, in a 100x100 box centred on the body ----
    // The canvas is larger than the item so dances, paws and the tail have
    // room to move without being clipped.
    Canvas {
        id: canvas

        anchors.centerIn: parent
        width: parent.width * 1.4
        height: parent.height * 1.4
        renderStrategy: Canvas.Cooperative

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const s = root.width / 100;
            c.translate(width / 2, height / 2 + 2 * s);
            c.scale(s, s);
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
        x: root.width * 0.68 + p.sway * root.width / 100
        y: root.height * 0.0 + p.bob * root.width / 100 + Math.sin(p.t * 4) * 2
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

        // petting: the cursor swinging across Emba a few times in a row
        property var strokes: []
        property real lastX: 0
        property int dir: 0

        onHoveredChanged: {
            if (hovered) {
                p.blinkLeft = 0.13;
                p.earL = p.earR = 0.4;   // ears perk up
                dwell.restart();
            } else
                dwell.stop();
        }
        onPointChanged: {
            const x = point.position.x;
            const d = Math.sign(x - lastX);
            if (Math.abs(x - lastX) > 2 && d && d !== dir) {
                const now = Date.now();
                strokes = strokes.filter(s => now - s < 1500).concat([now]);
                dir = d;
                if (strokes.length >= 4) {
                    strokes = [];
                    root.love();
                    p.syVel -= 1.2;
                    root.petted();
                }
            }
            lastX = x;
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

        longPressThreshold: 0.7
        onDoubleTapped: root.doubleClicked()
        onLongPressed: root.held()
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

    // ================================================================ drawing

    function shade(col, k) {
        return Qt.rgba(Math.min(1, col.r * k), Math.min(1, col.g * k), Math.min(1, col.b * k), 1);
    }

    // Built from points: Context2D.ellipse() mangles small ellipses, and Qt
    // applies the transform at fill time, so a scaled unit arc fails too.
    function ellipse(c, x, y, rx, ry) {
        c.beginPath();
        for (let i = 0; i < 28; i++) {
            const a = i / 28 * Math.PI * 2;
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
        const ring = shade(fur, 0.66);
        const pawCol = shade(fur, 0.5);

        // glow behind, in the mood colour
        if (p.glow > 0.01) {
            const g = c.createRadialGradient(0, 4, 8, 0, 4, 52);
            g.addColorStop(0, Qt.alpha(p.glowColor, p.glow * 0.55));
            g.addColorStop(1, Qt.alpha(p.glowColor, 0));
            c.fillStyle = g;
            ellipse(c, 0, 4, 52, 52);
            c.fill();
        }

        // ground shadow: smaller and fainter the higher Emba hops
        const lift = Math.max(0, -p.bob) / 18;
        c.fillStyle = `rgba(0,0,0,${0.22 * (1 - lift * 0.5)})`;
        ellipse(c, p.sway * 0.6, 39, 24 * (1 - lift * 0.35), 3.4 * (1 - lift * 0.35));
        c.fill();

        c.save();
        c.translate(p.sway, p.bob);
        // squash and stretch about the feet
        c.translate(0, 34);
        c.scale(p.sx, p.sy);
        c.translate(0, -34);
        c.rotate(p.roll + p.spin);

        // tail: a bushy striped curl that swishes behind
        for (let i = 0; i <= 6; i++) {
            const k = i / 6;
            const ang = -0.4 - k * 1.1 + p.tail * k;
            const tx = 24 + Math.cos(ang) * 6 + k * 13 + Math.sin(p.tail) * k * 6;
            const ty = 22 - k * 18 + Math.sin(ang) * 2;
            c.fillStyle = k > 0.85 ? dark : i % 2 === 1 ? ring : fur;
            ellipse(c, tx, ty, 8.6 - k * 2.2, 8.6 - k * 2.2);
            c.fill();
        }

        // feet peeking out at the bottom
        c.fillStyle = pawCol;
        for (const sx of [-1, 1]) {
            ellipse(c, 12 * sx, 33.5, 6, 3.6);
            c.fill();
        }

        // ears: round, fluffy cream inside, each twitching on its own
        for (const sx of [-1, 1]) {
            const twitch = sx < 0 ? p.earL : p.earR;
            c.save();
            c.translate(21 * sx, -18);
            c.rotate((0.3 + twitch * 0.6) * sx);
            c.fillStyle = fur;
            ellipse(c, 0, -2, 9.5, 10);
            c.fill();
            c.fillStyle = dark;
            ellipse(c, 0, -2.2, 5.6, 6.2);
            c.fill();
            c.fillStyle = cream;   // fluff at the base
            ellipse(c, 0, 2.6, 4.6, 2.4);
            c.fill();
            c.restore();
        }

        // body: one soft rounded square with gentle light from the top left
        squircle(c, 0, 4, 34, 28, 3);
        const body = c.createRadialGradient(-12, -14, 4, 0, 6, 46);
        body.addColorStop(0, shade(fur, 1.16));
        body.addColorStop(0.55, fur);
        body.addColorStop(1, shade(fur, 0.84));
        c.fillStyle = body;
        c.fill();
        c.save();
        squircle(c, 0, 4, 34, 28, 3);
        c.clip();
        c.fillStyle = "rgba(255,255,255,0.14)";
        ellipse(c, -8, -19, 22, 6.5);
        c.fill();
        c.restore();

        const fx = p.lookX * 6, fy = -p.lookY * 4;

        // red-panda brows: two cream dots
        c.fillStyle = cream;
        for (const sx of [-1, 1]) {
            ellipse(c, 10.5 * sx + fx, -9 + fy, 3.6, 2.5);
            c.fill();
        }

        // cream muzzle
        ellipse(c, fx * 1.05, 11 + fy, 9.5, 6.6);
        c.fillStyle = cream;
        c.fill();

        // blush, soft at the edge
        for (const sx of [-1, 1]) {
            const bx = 19 * sx + fx, by = 9 + fy;
            const g = c.createRadialGradient(bx, by, 0.5, bx, by, 5.5);
            const strong = e === "love" || p.purr > 0;
            g.addColorStop(0, strong ? "rgba(255,92,138,0.85)" : "rgba(255,140,165,0.6)");
            g.addColorStop(1, "rgba(255,140,165,0)");
            c.fillStyle = g;
            ellipse(c, bx, by, 5.5, 4);
            c.fill();
        }

        for (const sx of [-1, 1])
            drawEye(c, 10.5 * sx + fx, 1.5 + fy, sx, m, e);

        // nose and mouth
        const nx = fx * 1.1, ny = 8.4 + fy;
        c.fillStyle = dark;
        c.beginPath();
        c.moveTo(nx - 2.4, ny - 1);
        c.quadraticCurveTo(nx, ny - 1.8, nx + 2.4, ny - 1);
        c.quadraticCurveTo(nx + 1, ny + 1.6, nx, ny + 1.8);
        c.quadraticCurveTo(nx - 1, ny + 1.6, nx - 2.4, ny - 1);
        c.fill();
        if (p.mouth > 0.08) {
            c.fillStyle = "#6b2a2a";
            ellipse(c, nx, ny + 4.6 + p.mouth, 2 + p.mouth * 1.3, 0.8 + p.mouth * 2.8);
            c.fill();
            c.fillStyle = "#ff8a9a";   // tongue
            ellipse(c, nx, ny + 5.4 + p.mouth * 2, 1.4 + p.mouth * 0.7, p.mouth * 1.2);
            c.fill();
        } else {
            // the little "ω"
            c.strokeStyle = dark;
            c.lineWidth = 1.1;
            c.lineCap = "round";
            c.beginPath();
            c.moveTo(nx - 3.2, ny + 2.6);
            c.quadraticCurveTo(nx - 1.6, ny + 4.4, nx, ny + 2.4);
            c.quadraticCurveTo(nx + 1.6, ny + 4.4, nx + 3.2, ny + 2.6);
            c.stroke();
        }

        // a tiny laptop while an agent works
        if (p.laptop > 0.02) {
            c.globalAlpha = p.laptop;
            const ly = 30 - 4 * p.laptop;
            c.fillStyle = "#c7cdd8";
            c.beginPath();
            c.moveTo(-15, ly);
            c.lineTo(15, ly);
            c.lineTo(17, ly + 4);
            c.lineTo(-17, ly + 4);
            c.closePath();
            c.fill();
            c.fillStyle = "#8a93a3";
            c.fillRect(-13, ly + 0.8, 26, 1.2);
            // the screen glows back at Emba
            c.fillStyle = Qt.alpha(Theme.working, 0.35 + 0.15 * Math.sin(p.t * 5));
            c.fillRect(-11, ly - 1.2, 22, 1.2);
            c.globalAlpha = 1;
        }

        c.restore();

        // paws float beside the body; they rise to wave, clap, type, cheer
        for (const sx of [-1, 1]) {
            const arm = sx < 0 ? p.armL : p.armR;
            const x = p.sway + sx * (38 + p.pawSpread * 20 - arm * 2);  // spread < 0 brings paws in
            const y = p.bob + 22 - arm * 24 + Math.sin(p.t * 2 + sx) * 1.1;
            c.fillStyle = pawCol;
            ellipse(c, x, y, 5.6, 5.3);
            c.fill();
            if (arm > 0.55) {
                // toe beans show when the paw is up
                c.fillStyle = "#f2b5a8";
                ellipse(c, x, y + 1.2, 2.2, 1.7);
                c.fill();
                for (const bx of [-2.4, 0, 2.4]) {
                    ellipse(c, x + bx, y - 2.2, 0.9, 0.9);
                    c.fill();
                }
            }
        }
    }

    function drawEye(c, x, y, sx, m, e) {
        const ink = "#1e1a24";
        const sc = p.eyeScale;
        c.fillStyle = ink;
        c.strokeStyle = ink;
        c.lineCap = "round";
        c.lineWidth = 2.3;

        if (e === "love") {
            c.fillStyle = "#ff3f73";
            const r = 3.4 * sc;
            c.beginPath();
            c.moveTo(x, y + r * 1.3);
            c.bezierCurveTo(x - r * 2.2, y - r * 0.2, x - r * 0.9, y - r * 1.9, x, y - r * 0.6);
            c.bezierCurveTo(x + r * 0.9, y - r * 1.9, x + r * 2.2, y - r * 0.2, x, y + r * 1.3);
            c.fill();
            c.fillStyle = "rgba(255,255,255,0.8)";
            ellipse(c, x - r * 0.6, y - r * 0.4, r * 0.35, r * 0.3);
            c.fill();
            return;
        }
        if (e === "dizzy") {
            c.lineWidth = 1.6;
            c.beginPath();
            for (let a = 0; a < Math.PI * 5; a += 0.3) {
                const r = a * 0.4;
                const px = x + Math.cos(a + p.t * 9 * sx) * r, py = y + Math.sin(a + p.t * 9 * sx) * r;
                a === 0 ? c.moveTo(px, py) : c.lineTo(px, py);
            }
            c.stroke();
            return;
        }
        if (m === "error" && !e) {
            const r = 3.2;
            c.beginPath();
            c.moveTo(x - r, y - r); c.lineTo(x + r, y + r);
            c.moveTo(x + r, y - r); c.lineTo(x - r, y + r);
            c.stroke();
            return;
        }
        if (e === "happy" || (m === "done" && !e) || (p.act === "dance")) {
            c.beginPath();
            c.arc(x, y + 2, 3.8, Math.PI * 1.15, Math.PI * 1.85);
            c.stroke();
            return;
        }
        if (e === "annoyed") {
            c.beginPath();
            c.moveTo(x - 3.6 * sx, y - 2.8);
            c.lineTo(x + 3.2 * sx, y);
            c.lineTo(x - 3.6 * sx, y + 2.8);
            c.stroke();
            return;
        }

        const open = p.eyeOpen;
        if (open < 0.15) {
            // shut: a soft downward curve with a lash
            c.beginPath();
            c.arc(x, y - 1, 3.6, Math.PI * 0.15, Math.PI * 0.85);
            c.stroke();
            return;
        }
        const rx = 3.9 * sc, ry = 5.4 * sc * open;
        ellipse(c, x, y, rx, ry);
        c.fill();
        // a hint of colour low in the eye, then two catchlights
        c.fillStyle = "rgba(120,80,60,0.25)";
        ellipse(c, x, y + ry * 0.55, rx * 0.55, ry * 0.25);
        c.fill();
        c.fillStyle = "white";
        ellipse(c, x + 1.1 * sc, y - ry * 0.42, 1.25 * sc, 1.45 * sc * Math.min(1, open * 1.5));
        c.fill();
        ellipse(c, x - 1.2 * sc, y + ry * 0.38, 0.6 * sc, 0.6 * sc);
        c.fill();
        // tired: a flat lid across the top
        if ((m === "limit" || m === "sleepy") && !e) {
            c.fillStyle = root.bodyColor;
            c.fillRect(x - rx - 1, y - ry - 1, rx * 2 + 2, ry * 0.9);
        }
    }
}
