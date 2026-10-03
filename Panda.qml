import QtQuick
import QtQuick.Shapes
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
    // music is playing: dance whenever nothing else is going on
    property bool music: false
    // a bandana in this colour (transparent: none): which agent a little Emba stands for
    property color scarf: "transparent"
    // one accessory that tells the agents' Embas apart: glasses, headphones, sprout, cap (or none)
    property string outfit: ""

    signal clicked
    signal petted
    signal doubleClicked
    signal held
    // Emba made a sound-worthy move or face: the island decides whether to play it
    signal sound(string name)

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
    // a file goes in through the slot on top, which then shuts while Emba chews (as coucou's Mochi)
    function gulp() {
        p.gulpOpen = 0.3;
        p.chew = 1.1;
        p.syVel -= 2.2;
        p.sxVel += 1.8;
        emote("happy", 1.4);
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
        if (name !== p.emote || p.emoteLeft <= 0) {
            const s = ({ annoyed: "annoyed", dizzy: "dizzy", love: "love" })[name];
            if (s)
                sound(s);
        }
        p.emote = name;
        p.emoteLeft = seconds;
    }
    // a short routine: dance spin hop stretch wave lookaround tailchase sneeze
    function act(name) {
        if (["hop", "spin", "sneeze"].includes(name))
            sound(name);
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
        property real laptop: 0
        // timers
        property real nextBlink: 2
        property real blinkLeft: 0
        property real wanderLeft: 1
        property point wander: Qt.point(0, 0)
        property real mouthHold: 0
        // the head's own springs (see step)
        property real hx: 0
        property real hxVel: 0
        property real hy: 0
        property real hyVel: 0
        property real htilt: 0
        property real htiltVel: 0
        // the mailbox slot on top of the head: 0 shut, 1 wide open
        property real slot: 0
        property real slotVel: 0
        property real gulpOpen: 0
        property real chew: 0
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
        for (const c of sparkles.children) {
            if (c.age === undefined)
                continue;
            c.age += dt;
            if (c.age > 1.2)
                c.destroy();
        }
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
        if (root.music && ["idle", "lonely", "done"].includes(m) && !e && !root.eager && !p.act)
            act("dance");
        else if (root.lively && calm && !p.act) {
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
                    burst("♪", "#ffffff", 1);
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

        // the slot springs open while a file hovers, wide for the gulp, shut otherwise
        p.gulpOpen = Math.max(0, p.gulpOpen - dt);
        const slotTo = p.gulpOpen > 0 ? 1 : root.eager ? 0.45 : 0;
        p.slotVel += (380 * (slotTo - p.slot) - 2 * 0.7 * Math.sqrt(380) * p.slotVel) * dt;
        p.slot = Math.max(0, p.slot + p.slotVel * dt);
        if (p.chew > 0 && p.gulpOpen <= 0) {
            p.chew -= dt;
            mouth = Math.abs(Math.sin(t * 15)) * 0.55;
        }
        if (root.eager) {
            mouth = 0.25;
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
        // the head rides on its own, softer springs: it lags behind a hop or a sway and settles
        // with a little overshoot, breathes when calm, and tilts toward what Emba looks at
        const breathe = (m === "idle" || m === "sleepy" || m === "lonely") ? Math.sin(t * 1.9) * 0.7 : 0;
        p.hxVel += (-170 * (p.hx - p.sway) - 9 * p.hxVel) * dt;
        p.hx += p.hxVel * dt;
        p.hyVel += (-190 * (p.hy - (p.bob + breathe)) - 9 * p.hyVel) * dt;
        p.hy += p.hyVel * dt;
        p.htiltVel += (-150 * (p.htilt - (p.lookX * 0.16 + (p.sway - p.hx) * 0.02)) - 8 * p.htiltVel) * dt;
        p.htilt += p.htiltVel * dt;
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
        // and they flop a little as the head bounces
        const flop = Math.max(-0.5, Math.min(0.5, -p.hyVel * 0.006));
        p.earL = approach(p.earL, earL + twitchL + flop, 14, dt);
        p.earR = approach(p.earR, earR + twitchR + flop, 14, dt);

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


        spawnParticles(m, e, dt);
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
            particle.createObject(sparkles, {
                text: glyph,
                color: colour,
                x: root.width / 2 + (sweat ? 30 * s : (Math.random() * 60 - 30) * s),
                y: root.height / 2 - (sweat ? 10 : 40) * s,
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
        bit.createObject(sparkles, {
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

        // stepped by Emba's own timer (see step): an animation here would run
        // at full refresh rate and cost ~10% CPU while dancing
        Text {
            id: pt

            property real dx
            property real dy
            property real px
            property real x0
            property real y0
            property real age: 0
            readonly property real k: 1 - Math.pow(1 - Math.min(1, age / 1.2), 2)  // ease out

            Component.onCompleted: { x0 = x; y0 = y; }
            x: x0 + dx * k
            y: y0 + dy * k
            scale: 0.4 + 0.8 * k
            rotation: -15 + 30 * Math.min(1, age / 1.2)
            opacity: age < 0.15 ? age / 0.15 : age < 0.8 ? 1 : Math.max(0, 1 - (age - 0.8) / 0.4)
            font.pixelSize: px
            font.bold: true
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

    // Frames are capped: a soft little creature looks just as smooth at 30 fps,
    // and drawing is what costs. The island asks for less when Emba is small.
    property real pending: 0
    property point lastGaze

    // Moving: full rate. Just breathing and blinking: 10 fps is plenty, and
    // it is most of the time.
    function busy() {
        const g = root.gaze, moved = g && Math.hypot(g.x - lastGaze.x, g.y - lastGaze.y) > 3;
        if (g)
            lastGaze = g;
        return moved || sparkles.children.length > 0 || p.act !== "" || p.emoteLeft > 0 || p.spinLeft > 0 || p.shakeLeft > 0 || p.purr > 0 || p.mouthHold > 0 || p.slot > 0.01 || p.chew > 0 || Math.abs(p.bobVel) > 4 || Math.abs(p.hyVel) > 2 || Math.abs(p.hxVel) > 2 || Math.abs(p.htiltVel) > 0.05 || Math.abs(p.syVel) > 0.05 || Math.abs(p.sxVel) > 0.05 || root.talk > 0 || root.eager || hover.hovered || ["working", "waiting", "question", "done", "listening", "thinking", "error"].includes(root.mood);
    }

    // Two clocks. While Emba moves, a FrameAnimation steps it once per screen
    // refresh (60 Hz or more): motion as smooth as the display allows. While it
    // only breathes and blinks, a 10 Hz timer is enough, and the render loop
    // can sleep in between (a FrameAnimation would keep it awake for nothing).
    property bool moving: true
    property real lastTick: 0
    // false where Emba is tiny (the pill): a steady 30 fps timer instead of
    // every display refresh, so the render loop can sleep between frames
    property bool smooth: true

    function advance() {
        const now = Date.now();
        const dt = lastTick ? (now - lastTick) / 1000 : 0.016;
        lastTick = now;
        // springs go unstable past ~1/20 s per step: slow ticks take several
        for (let left = Math.min(dt, 0.25); left > 1e-4; left -= 0.04)
            step(Math.min(left, 0.04));
        moving = busy();
    }

    FrameAnimation {
        running: root.running && root.moving && root.smooth
        onTriggered: root.advance()
    }
    Timer {
        running: root.running && (!root.moving || !root.smooth)
        interval: root.moving ? 33 : 100
        repeat: true
        onTriggered: root.advance()
    }
    onRunningChanged: lastTick = 0

    // ---- drawing ----
    // Emba is built from scene-graph items (circles, ellipses, vector shapes)
    // in a 100x100 unit space centred on the body. Each frame only moves and
    // reshapes them; the GPU does the drawing, so Emba costs almost nothing
    // to animate. `e` is the current emote, `m` the mood.
    readonly property string e: p.emoteLeft > 0 ? p.emote : ""
    readonly property string m: root.mood
    readonly property color fur: root.bodyColor
    readonly property color dark: "#3a2420"
    readonly property color cream: "#fff4e8"
    readonly property color belly: shade(fur, 0.42)  // the dark body, tail stripes
    readonly property real fx: p.lookX * 6
    readonly property real fy: -p.lookY * 4
    // which kind of eyes to show
    readonly property string eyes: e === "love" ? "love" : e === "dizzy" ? "dizzy" : (m === "error" && !e) ? "x" : (e === "happy" || (m === "done" && !e) || p.act === "dance") ? "happy" : e === "annoyed" ? "annoyed" : p.eyeOpen < 0.15 ? "shut" : "open"
    // a new expression comes in behind a quick blink instead of snapping over
    // (a blink itself is "shut" then "open" again: that is not a new expression)
    property string lastEyes: "open"
    onEyesChanged: {
        if (eyes !== "shut" && eyes !== lastEyes && p.blinkLeft <= 0)
            p.blinkLeft = 0.09;
        if (eyes !== "shut")
            lastEyes = eyes;
    }

    // an ellipse: a circle squashed vertically, so it stays a true ellipse
    component Ell: Rectangle {
        property real cx
        property real cy
        property real rx: 1
        property real ry: rx

        x: cx - rx
        y: cy - rx
        width: rx * 2
        height: rx * 2
        radius: rx
        antialiasing: true
        transform: Scale {
            origin.x: rx
            origin.y: rx
            yScale: ry / Math.max(rx, 0.001)
        }
    }

    // a stroked or filled vector path in unit coordinates
    component VPath: Shape {
        id: vp

        property string d
        property color fill: "transparent"
        property color stroke: "transparent"
        property real line: 0

        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: vp.fill
            strokeColor: vp.stroke
            strokeWidth: vp.line
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: vp.d
            }
        }
    }

    Item {
        id: units

        x: root.width / 2
        y: root.height / 2 + 2 * root.width / 100
        scale: root.width / 100
        transformOrigin: Item.TopLeft

        // ground shadow: smaller and fainter the higher Emba hops
        Ell {
            readonly property real lift: Math.max(0, -p.bob) / 18

            cx: p.sway * 0.6
            cy: 39
            rx: 24 * (1 - lift * 0.35)
            ry: 3.4 * (1 - lift * 0.35)
            color: Qt.rgba(0, 0, 0, 0.22 * (1 - lift * 0.5))
        }

        // everything that moves with the body
        Item {
            id: body

            transform: [
                Rotation { angle: (p.roll + p.spin) * 180 / Math.PI },
                Scale { origin.y: 34; xScale: p.sx; yScale: p.sy },
                Translate { x: p.sway; y: p.bob }
            ]

            // tail: a striped curl that swishes behind, from the side of the body up past the head
            Repeater {
                model: 5

                Ell {
                    required property int index
                    readonly property real k: index / 4
                    readonly property real ang: -0.4 - k * 1.1 + p.tail * k

                    cx: 18 + Math.cos(ang) * 5 + k * 12 + Math.sin(p.tail) * k * 6
                    cy: 31 - k * 20 + Math.sin(ang) * 2
                    rx: 7.6 - k * 1.8
                    color: k > 0.85 ? root.dark : index % 2 === 1 ? root.belly : root.fur
                }
            }

            // a small dark body, and its feet
            Rectangle { x: -16; y: 8; width: 32; height: 30; radius: 8; color: root.belly }
            Rectangle { x: -19; y: 34.5; width: 12; height: 5.5; radius: 2.75; color: root.dark }
            Rectangle { x: 7; y: 34.5; width: 12; height: 5.5; radius: 2.75; color: root.dark }

            // the bandana, around the neck where head meets body
            VPath {
                visible: root.scarf.a > 0
                fill: root.scarf
                d: "M -19 10.5 Q 0 15.5 19 10.5 L 18 20 Q 0 25 -18 20 Z"
            }
            VPath {
                visible: root.scarf.a > 0
                fill: root.shade(root.scarf, 0.82)
                d: "M 5 19.5 L 11.5 30 L 17 18.5 Z"
            }

            // ears: round, rimmed in cream, dark inside; each twitches on its own
            Repeater {
                model: [-1, 1]

                Item {
                    required property int modelData

                    x: 21 * modelData
                    y: -30
                    rotation: (0.15 + (modelData < 0 ? p.earL : p.earR) * 0.6) * modelData * 180 / Math.PI

                    Ell { cx: 0; cy: -2; rx: 10.5; ry: 10; color: root.cream }
                    Ell { cx: 0; cy: 0; rx: 7; ry: 7; color: root.dark }
                }
            }

            // the head and everything on it, on its own springs: it follows the body a beat late
            Item {
                id: head

                // plain x/y/rotation: one transform node, cheaper than a transform list
                x: (p.hx - p.sway) * 0.8
                y: Math.max(-6, Math.min(6, p.hy - p.bob))
                rotation: p.htilt * 180 / Math.PI
                transformOrigin: Item.TopLeft

                // headphones: the band goes behind the head, the cups over the ears' sides
                VPath {
                    visible: root.outfit === "headphones"
                    d: "M -31 -14 Q -31 -44 0 -44 Q 31 -44 31 -14"
                    stroke: "#2b2d36"
                    line: 4.5
                }

                // the head: one wide flat block, no shading
                Rectangle { x: -32; y: -32; width: 64; height: 48; radius: 16; color: root.fur }

                // accessories that sit on the head
                Item {
                    visible: root.outfit === "headphones"

                    Rectangle { x: -38; y: -20; width: 9; height: 18; radius: 4.5; color: "#2b2d36" }
                    Rectangle { x: 29; y: -20; width: 9; height: 18; radius: 4.5; color: "#2b2d36" }
                    Rectangle { x: -36.5; y: -17; width: 3; height: 12; radius: 1.5; color: root.scarf.a > 0 ? root.scarf : "#5b9cf6" }
                    Rectangle { x: 33.5; y: -17; width: 3; height: 12; radius: 1.5; color: root.scarf.a > 0 ? root.scarf : "#5b9cf6" }
                }
                Item {
                    visible: root.outfit === "sprout"

                    VPath { d: "M 0 -31 Q 1 -38 -1 -44"; stroke: "#3f8f4e"; line: 2.4 }
                    VPath { d: "M -1 -42 Q -12 -48 -13 -38 Q -6 -36 -1 -42 Z"; fill: "#57b36a" }
                    VPath { d: "M -0.5 -40 Q 9 -49 13 -41 Q 6 -36 -0.5 -40 Z"; fill: "#6cc97e" }
                }
                Item {
                    visible: root.outfit === "cap"

                    VPath { d: "M -27 -26 Q -26 -45 0 -45 Q 26 -45 27 -26 Z"; fill: root.scarf.a > 0 ? root.scarf : "#c084fc" }
                    VPath { d: "M 12 -30 Q 30 -33 38 -27 Q 30 -24 12 -26 Z"; fill: root.shade(root.scarf.a > 0 ? root.scarf : "#c084fc", 0.75) }
                    Rectangle { x: -2; y: -47; width: 4; height: 3; radius: 1.5; color: root.shade(root.scarf.a > 0 ? root.scarf : "#c084fc", 0.75) }
                }

                // the mailbox slot on top of the head: widens first, then opens up
                Rectangle {
                    readonly property real w: 36 * Math.min(1, p.slot * 2.4)
                    readonly property real h: Math.min(11, 11 * p.slot)

                    visible: p.slot > 0.02
                    x: -w / 2
                    y: -29
                    width: w
                    height: h
                    radius: Math.min(w, h) / 2
                    color: "#0b0b0e"
                }

                // the face moves a little with the gaze
                Item {
                    x: root.fx
                    y: root.fy

                    // cheek patches and the muzzle: the red panda's mask
                    Ell { cx: -19; cy: -1; rx: 8; ry: 6; color: root.cream }
                    Ell { cx: 19; cy: -1; rx: 8; ry: 6; color: root.cream }
                    Ell { cx: 0; cy: 2; rx: 9; ry: 6; color: root.cream }
    
                    // blush, only when it's loved
                    Repeater {
                        model: [-1, 1]

                        Ell {
                            required property int modelData

                            visible: root.e === "love" || p.purr > 0
                            cx: 19 * modelData
                            cy: -1
                            rx: 5
                            ry: 3.4
                            color: Qt.rgba(1, 0.36, 0.54, 0.75)
                        }
                    }

                    // eyes
                    Repeater {
                        model: [-1, 1]

                        Item {
                            id: eye

                            required property int modelData
                            readonly property real sc: p.eyeScale
                            readonly property real open: p.eyeOpen
                            readonly property color ink: "#1e1512"

                            x: 10 * modelData
                            y: -8

                            // open: a plain dot
                            Item {
                                visible: root.eyes === "open"

                                Ell { cx: 0; cy: 0; rx: 3.4 * eye.sc; ry: 3.6 * eye.sc * eye.open; color: eye.ink }
                                // tired: a flat lid across the top
                                Rectangle {
                                    visible: (root.m === "limit" || root.m === "sleepy") && !root.e
                                    x: -4.2 * eye.sc
                                    y: -3.6 * eye.sc * eye.open - 1
                                    width: 8.4 * eye.sc
                                    height: 3.6 * eye.sc * eye.open * 0.9
                                    color: root.fur
                                }
                            }
                            VPath {
                                visible: root.eyes === "shut"
                                d: "M -3 0 Q 0 2.8 3 0"
                                stroke: eye.ink
                                line: 2.2
                            }
                            VPath {
                                visible: root.eyes === "happy"
                                d: "M -3 1 Q 0 -2.4 3 1"
                                stroke: eye.ink
                                line: 2.2
                            }
                            VPath {
                                visible: root.eyes === "x"
                                d: "M -2.8 -2.8 L 2.8 2.8 M 2.8 -2.8 L -2.8 2.8"
                                stroke: eye.ink
                                line: 2.2
                            }
                            VPath {
                                visible: root.eyes === "annoyed"
                                d: `M ${-3.4 * eye.modelData} -2.6 L ${3 * eye.modelData} 0 L ${-3.4 * eye.modelData} 2.6`
                                stroke: eye.ink
                                line: 2.2
                            }
                            VPath {
                                visible: root.eyes === "love"
                                d: "M 0 4 C -7 -0.6 -2.9 -6 0 -1.8 C 2.9 -6 7 -0.6 0 4 Z"
                                fill: "#e3122f"  // a proper red heart
                                scale: eye.sc
                            }
                            VPath {
                                visible: root.eyes === "dizzy"
                                d: root.spiralPath
                                stroke: eye.ink
                                line: 1.4
                                rotation: p.t * 9 * eye.modelData * 180 / Math.PI
                            }
                        }
                    }

                    // round glasses
                    Item {
                        visible: root.outfit === "glasses"

                        Ell { cx: -10; cy: -8; rx: 6.2; color: Qt.rgba(1, 1, 1, 0.16) }
                        Ell { cx: 10; cy: -8; rx: 6.2; color: Qt.rgba(1, 1, 1, 0.16) }
                        VPath { d: "M -16.2 -8 A 6.2 6.2 0 1 0 -3.8 -8 A 6.2 6.2 0 1 0 -16.2 -8 M 3.8 -8 A 6.2 6.2 0 1 0 16.2 -8 A 6.2 6.2 0 1 0 3.8 -8 M -3.8 -9 Q 0 -11 3.8 -9"; stroke: "#2b1a14"; line: 1.6 }
                    }

                    // nose; a mouth only when it opens (talking, surprised, eating)
                    VPath {
                        d: "M -3 -1 L 3 -1 L 0 2.2 Z"
                        fill: root.dark
                    }
                    Ell {
                        visible: p.mouth > 0.08
                        cx: 0
                        cy: 4.8 + p.mouth
                        rx: 1.8 + p.mouth * 1.2
                        ry: 0.8 + p.mouth * 2.4
                        color: "#5e2420"
                    }
                }

            }

            // a tiny laptop while an agent works
            Item {
                visible: p.laptop > 0.02
                opacity: p.laptop
                y: 31 - 4 * p.laptop

                VPath {
                    d: "M -15 0 L 15 0 L 17 4 L -17 4 Z"
                    fill: "#c7cdd8"
                }
                Rectangle { x: -13; y: 0.8; width: 26; height: 1.2; color: "#8a93a3" }
                Rectangle {
                    x: -11
                    y: -1.2
                    width: 22
                    height: 1.2
                    color: Qt.alpha(Theme.working, 0.35 + 0.15 * Math.sin(p.t * 5))
                }
            }
        }

        // paws float beside the body; they rise to wave, clap, type, cheer
        Repeater {
            model: [-1, 1]

            Item {
                id: paw

                required property int modelData
                readonly property real arm: modelData < 0 ? p.armL : p.armR

                x: p.sway + modelData * (22 + p.pawSpread * 20 - arm * 2)
                y: p.bob + 26 - arm * 26 + Math.sin(p.t * 2 + modelData) * 1.1

                Ell { cx: 0; cy: 0; rx: 5; ry: 4.8; color: root.dark }
            }
        }
    }

    readonly property string spiralPath: {
        let d = "";
        for (let a = 0; a < Math.PI * 5; a += 0.3) {
            const r = a * 0.4;
            d += `${a ? "L" : "M"} ${(Math.cos(a) * r).toFixed(2)} ${(Math.sin(a) * r).toFixed(2)} `;
        }
        return d;
    }

    Item {
        id: sparkles

        anchors.fill: parent
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
        onDoubleTapped: {
            taps = [];  // a double-click is a feed, not two-thirds of a dizzy
            root.doubleClicked();
        }
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

}
