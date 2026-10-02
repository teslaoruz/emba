import QtQuick
import QtMultimedia
import Quickshell

// Emba's sound effects (assets/sounds, made by dev/make_sounds.py). Loaded on
// its own by the island: where Qt has no audio module, this file simply fails
// to load and Emba stays quiet instead of breaking.
Item {
    id: root

    readonly property string dir: {
        const d = `${Quickshell.shellDir}/assets/sounds`.replace(/\\/g, "/");
        return d.startsWith("/") ? `file://${d}` : `file:///${d}`;
    }
    readonly property var names: ["open", "close", "hi", "ask", "done", "low", "gulp", "boop", "annoyed", "dizzy", "love", "eat", "play", "yawn", "wake", "hop", "spin", "sneeze", "listen"]

    function play(name, volume) {
        const s = effects.objectAt(names.indexOf(name));
        if (!s)
            return;
        s.volume = volume;
        s.play();
    }

    // one preloaded effect per sound: no decoding when it's time to play
    Instantiator {
        id: effects

        model: root.names

        SoundEffect {
            required property string modelData

            source: `${root.dir}/${modelData}.wav`
        }
    }
}
