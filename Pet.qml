pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Emba as a little pet. Food, joy and energy drift with real time (also while
// Emba is closed) and are saved, but never shown as numbers: Emba just acts
// hungry, sleepy or lonely, and perks up when you pet, feed or play with it.
// Nothing bad ever happens; a neglected Emba is only mopey until you're back.
Singleton {
    id: root

    readonly property bool on: App.cfg.pet ?? true
    property real food: 80
    property real joy: 80
    property real energy: 80
    property bool napping: false
    property real lastFed: 0
    property real lastPet: 0
    property bool ready: false

    // what Emba wants most right now, if anything
    readonly property string need: !on || napping ? "" : food < 30 ? "hungry" : energy < 25 ? "sleepy" : joy < 30 ? "lonely" : ""

    signal fed
    signal played
    signal petted
    signal refused(string why)

    readonly property string path: `${Quickshell.env("XDG_STATE_HOME") || (Qt.platform.os === "windows" ? Quickshell.env("LOCALAPPDATA") : Quickshell.env("HOME") + "/.local/state")}/emba/pet.json`

    function clamp(v) {
        return Math.max(5, Math.min(100, v));  // never all the way to zero
    }

    // hours of real time pass; busy sessions tire Emba, quiet time rests it
    function tick(hours) {
        const busy = App.sessions.filter(s => s.state === "working" || s.state === "thinking").length;
        food = clamp(food - 4 * hours);
        joy = clamp(joy - 3 * hours);
        energy = clamp(energy + (napping ? 20 : busy ? -2 * busy : 6) * hours);
        if (napping && energy >= 100)
            napping = false;
    }

    function pet() {
        if (!on || Date.now() - lastPet < 4000)
            return;
        lastPet = Date.now();
        joy = clamp(joy + 8);
        root.petted();
        save();
    }

    function feed() {
        if (!on)
            return;
        if (Date.now() - lastFed < 20 * 60000 && food > 70)
            return root.refused("full");
        lastFed = Date.now();
        food = clamp(food + 35);
        joy = clamp(joy + 4);
        root.fed();
        save();
    }

    function play() {
        if (!on)
            return;
        if (energy < 20)
            return root.refused("tired");
        joy = clamp(joy + 15);
        energy = clamp(energy - 8);
        food = clamp(food - 3);
        root.played();
        save();
    }

    function nap() {
        napping = !napping;
        save();
    }

    function save() {
        if (!ready)
            return;
        mkdir.text = JSON.stringify({
            food: food,
            joy: joy,
            energy: energy,
            napping: napping,
            lastFed: lastFed,
            lastPet: lastPet,
            seen: Date.now()
        });
        mkdir.running = true;
    }

    FileView {
        id: file

        path: root.path
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.food = s.food ?? 80;
                root.joy = s.joy ?? 80;
                root.energy = s.energy ?? 80;
                root.napping = !!s.napping;
                root.lastFed = s.lastFed ?? 0;
                root.lastPet = s.lastPet ?? 0;
                // catch up on the time Emba was closed, up to two days
                root.tick(Math.min(48, Math.max(0, (Date.now() - (s.seen ?? Date.now())) / 3600000)));
            } catch (e) {}
            root.ready = true;
        }
        onLoadFailed: root.ready = true
    }

    Process {
        id: mkdir

        property string text

        command: ["mkdir", "-p", root.path.replace(/[\\/][^\\/]*$/, "")]
        onExited: file.setText(text)
    }

    Timer {
        running: root.on && root.ready
        interval: 60000
        repeat: true
        onTriggered: {
            root.tick(1 / 60);
            root.save();
        }
    }

    // finishing work together makes Emba happy
    Connections {
        target: App

        function onFinished(sid) {
            root.joy = root.clamp(root.joy + 3);
        }
    }
}
