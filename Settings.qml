pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// The settings page: `emba settings`, the gear on the island, or the desktop
// entry. Each host wraps it in its own window. Every control writes straight
// to Emba's config file. Short labels, one switch per line.
Rectangle {
    id: win

    implicitWidth: 440
    implicitHeight: 660
    color: Theme.base

    readonly property var st: App.status
    readonly property var agentNames: ({
            claude: "Claude Code",
            codex: "Codex",
            opencode: "opencode",
            gemini: "Gemini CLI"
        })
    // how to get each agent, for "Add an agent"
    readonly property var agentInstall: ({
            claude: "npm install -g @anthropic-ai/claude-code",
            codex: "npm install -g @openai/codex",
            opencode: "curl -fsSL https://opencode.ai/install | bash",
            gemini: "npm install -g @google/gemini-cli"
        })
    // only agents on this computer (or still hooked up) are worth a line
    readonly property var agents: Object.keys(agentNames).filter(a => st.agents?.[a]?.installed || st.agents?.[a]?.connected)
    readonly property var missing: Object.keys(agentNames).filter(a => !agents.includes(a))
    property bool adding: false

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 40
        clip: true

        ColumnLayout {
            id: col

            x: 24
            y: 20
            width: parent.width - 48
            spacing: 12

            RowLayout {
                spacing: 12

                Panda {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    bodyColor: App.cfg.color
                    mood: Pet.need || "idle"
                    Component.onCompleted: wave()
                }
                ColumnLayout {
                    spacing: 0

                    Text {
                        text: "Emba"
                        color: Theme.text
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: win.st.version ? `your coding buddy · ${win.st.version}` : "your coding buddy"
                        color: Theme.dim
                        font.pixelSize: 12
                    }
                }
            }

            // ---- agents ----
            Section { text: "Agents" }

            Card {
                Repeater {
                    model: win.agents

                    Toggle {
                        required property string modelData

                        text: win.agentNames[modelData]
                        dot: App.agentColour(modelData)
                        hint: !win.st.agents?.[modelData]?.connected ? "not watched yet" : ""
                        checked: !!win.st.agents?.[modelData]?.connected
                        enabled: !App.busy
                        onToggled: on => App.run([on ? "connect" : "disconnect", modelData])
                    }
                }
                Text {
                    visible: win.agents.length === 0
                    text: "No coding agent found on this computer yet."
                    color: Theme.dim
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                // add another: how to install the ones that aren't here, and the hook for any other
                Button {
                    visible: !win.adding
                    text: "Add an agent"
                    onClicked: win.adding = true
                }
                ColumnLayout {
                    visible: win.adding
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: win.missing

                        ColumnLayout {
                            id: miss

                            required property string modelData

                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                spacing: 8

                                Rectangle { width: 8; height: 8; radius: 4; color: App.agentColour(miss.modelData) }
                                Text {
                                    text: win.agentNames[miss.modelData]
                                    color: Theme.text
                                    font.pixelSize: 13
                                }
                            }
                            Command { text: win.agentInstall[miss.modelData] }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.missing.length ? "Run that in a terminal, then switch it on here." : "Every agent Emba knows is here."
                        color: Theme.faint
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Any other agent"
                            color: Theme.text
                            font.pixelSize: 13
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "If it has Claude Code style hooks, point them at this, with your agent's name:"
                            color: Theme.faint
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                        Command { text: `${App.hookPath} --agent my-agent` }
                    }
                    Button {
                        text: "Done"
                        onClicked: {
                            win.adding = false;
                            App.refreshStatus();
                        }
                    }
                }
            }

            // ---- more agent options ----
            Card {
                Labelled {
                    visible: (win.st.ask ?? []).length > 1
                    text: "Ask with"
                    Segmented {
                        options: [["auto", "auto"]].concat((win.st.ask ?? []).map(t => [t, t]))
                        value: App.cfg.askWith ?? "auto"
                        onPicked: v => App.setCfg({ askWith: v })
                    }
                }
                Toggle {
                    visible: !!win.st.agents?.claude?.connected
                    text: "Show Claude usage"
                    checked: !!win.st.agents?.claude?.statusline
                    enabled: !App.busy
                    onToggled: on => App.run(on ? ["connect", "claude", "--statusline"] : ["connect", "claude"])
                }
                Toggle {
                    visible: !!win.st.tray
                    text: "Icon in the system tray"
                    checked: App.cfg.tray !== false
                    onToggled: on => App.setCfg({ tray: on })
                }
                Toggle {
                    text: "Start when I log in"
                    checked: !!win.st.autostart
                    enabled: !App.busy
                    onToggled: on => App.run(["autostart", on ? "on" : "off"])
                }
            }

            // ---- place ----
            Section { text: "Where" }

            Card {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18

                    // a little screen with eight spots
                    Rectangle {
                        width: 120
                        height: 76
                        radius: 10
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.border

                        Grid {
                            anchors.fill: parent
                            anchors.margins: 6
                            columns: 3

                            Repeater {
                                model: ["top-left", "top", "top-right", "left", "", "right", "bottom-left", "bottom", "bottom-right"]

                                Item {
                                    id: spot

                                    required property string modelData
                                    readonly property bool on: App.cfg.position === modelData

                                    width: 36
                                    height: 21

                                    Rectangle {
                                        visible: spot.modelData !== ""
                                        anchors.centerIn: parent
                                        width: spot.on ? 24 : 16
                                        height: spot.on ? 11 : 7
                                        radius: height / 2
                                        color: spot.on ? App.cfg.color : spotHover.hovered ? Theme.dim : Theme.faint

                                        Behavior on width { NumberAnimation { duration: 160 } }
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }
                                    HoverHandler {
                                        id: spotHover

                                        enabled: spot.modelData !== ""
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                    TapHandler {
                                        enabled: spot.modelData !== ""
                                        onTapped: App.setCfg({ position: spot.modelData })
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Labelled {
                            text: "Size"
                            Segmented {
                                options: [["S", 0.85], ["M", 1], ["L", 1.2]]
                                value: App.cfg.scale
                                onPicked: v => App.setCfg({ scale: v })
                            }
                        }
                        Labelled {
                            visible: Quickshell.screens.length > 1
                            text: "Screen"
                            Segmented {
                                options: [["Main", ""]].concat(Quickshell.screens.map(s => [s.name, s.name]))
                                value: App.cfg.screen
                                onPicked: v => App.setCfg({ screen: v })
                            }
                        }
                    }
                }
            }

            // ---- look ----
            Section { text: "Look" }

            Card {
                Toggle {
                    text: "Match my desktop colours"
                    hint: App.cfg.theme !== "default" && Theme.source !== "default" ? `using ${Theme.source}` : ""
                    checked: App.cfg.theme !== "default"
                    onToggled: on => App.setCfg({ theme: on ? "auto" : "default" })
                }
                Labelled {
                    text: "Fur"
                    Row {
                        spacing: 8

                        Repeater {
                            model: ["#e2683c", "#c8503a", "#a8643c", "#e88a5b", "#d9a05b", "#8a6f5c"]

                            Rectangle {
                                id: swatch

                                required property string modelData

                                width: 22
                                height: 22
                                radius: 11
                                color: modelData
                                border.width: App.cfg.color === modelData ? 3 : 0
                                border.color: Theme.text

                                TapHandler { onTapped: App.setCfg({ color: swatch.modelData }) }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }
            }

            // ---- voice ----
            Section { text: "Voice" }

            Card {
                // not installed: one button, and what it costs
                RowLayout {
                    visible: !win.st.voice
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Talk to Emba, and hear it answer"
                            color: Theme.text
                            font.pixelSize: 13
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Free speech models, about 250 MB. Nothing you say leaves this computer."
                            color: Theme.faint
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                    }
                    Button {
                        text: App.busy ? "Installing…" : "Install"
                        primary: true
                        onClicked: App.run(["voice-install"])
                    }
                }

                // installed: listening and talking back are separate switches
                Toggle {
                    visible: !!win.st.voice
                    text: "Talk to Emba"
                    hint: "shake the mouse, or say “Hey Emba”"
                    checked: !!App.cfg.voice
                    onToggled: on => App.setCfg({ voice: on })
                }
                Toggle {
                    visible: !!win.st.voice && !!App.cfg.voice
                    indent: true
                    text: "Shake the mouse to talk"
                    checked: !!App.cfg.voiceShake
                    onToggled: on => App.setCfg({ voiceShake: on })
                }
                Toggle {
                    visible: !!win.st.voice && !!App.cfg.voice
                    indent: true
                    text: "Listen for “Hey Emba”"
                    hint: "keeps the microphone on"
                    checked: !!App.cfg.voiceWake
                    onToggled: on => App.setCfg({ voiceWake: on })
                }
                Toggle {
                    visible: !!win.st.voice
                    text: "Talk back"
                    hint: "Emba reads its answers aloud"
                    checked: !!App.cfg.voiceReply
                    onToggled: on => App.setCfg({ voiceReply: on })
                }
                Labelled {
                    visible: !!win.st.voice && !!App.cfg.voiceReply
                    text: "Voice"
                    Segmented {
                        options: [["Amy", "en_US-amy-medium"], ["Ryan", "en_US-ryan-medium"], ["Alba", "en_GB-alba-medium"]]
                        value: App.cfg.voiceName
                        onPicked: v => {
                            App.setCfg({ voiceName: v });
                            Qt.callLater(() => App.say("Hi! This is how I sound."));
                        }
                    }
                }
                Link {
                    visible: !!win.st.voice
                    text: App.busy ? "removing…" : "Remove voice and its models"
                    onClicked: App.run(["voice-remove"])
                }
            }

            // ---- emba ----
            Section { text: "Emba" }

            Card {
                Toggle {
                    text: "Gets hungry and sleepy"
                    hint: "a little pet to look after"
                    checked: App.cfg.pet !== false
                    onToggled: on => App.setCfg({ pet: on })
                }
                Toggle {
                    text: "Pop up when an agent asks"
                    checked: App.cfg.autoOpenOnPermission
                    onToggled: on => App.setCfg({ autoOpenOnPermission: on })
                }
                Toggle {
                    text: "Cheer when work is done"
                    checked: App.cfg.celebrate
                    onToggled: on => App.setCfg({ celebrate: on })
                }
                Toggle {
                    text: "Hide when nothing is running"
                    checked: App.cfg.hideWhenIdle
                    onToggled: on => App.setCfg({ hideWhenIdle: on })
                }
                Toggle {
                    text: "Sounds"
                    hint: "a pop, a chime when an agent asks, a jingle when it's done"
                    checked: !!App.cfg.sounds
                    onToggled: on => App.setCfg({ sounds: on })
                }
                Labelled {
                    visible: !!App.cfg.sounds
                    text: "Volume"
                    Segmented {
                        options: [["Quiet", 0.25], ["Normal", 0.5], ["Loud", 0.9]]
                        value: App.cfg.soundVolume ?? 0.5
                        onPicked: v => App.setCfg({ soundVolume: v })
                    }
                }
                Toggle {
                    text: "Dance when music plays"
                    checked: App.cfg.danceToMusic
                    onToggled: on => App.setCfg({ danceToMusic: on })
                }
                Toggle {
                    text: "Eyes follow the mouse"
                    checked: App.cfg.trackCursor
                    onToggled: on => App.setCfg({ trackCursor: on })
                }
            }

            // ---- integrations: a key each, kept in the system keyring ----
            Section { text: "Integrations" }

            Card {
                Component.onCompleted: App.refreshKeys()

                Text {
                    Layout.fillWidth: true
                    text: "Paste a key to see a line from that service in the island. Keys stay in your system keyring, never in a file."
                    color: Theme.faint
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: [
                        ["vercel", "Vercel", "deployments", "vercel.com/account/tokens"],
                        ["stripe", "Stripe", "today's payments (a restricted, read-only key is enough)", "dashboard.stripe.com/apikeys"],
                        ["resend", "Resend", "recent emails and bounces", "resend.com/api-keys"],
                        ["calcom", "Cal.com", "your next booking", "app.cal.com/settings/developer/api-keys"],
                        ["notion", "Notion", "the page you edited last", "notion.so/my-integrations"],
                        ["n8n", "n8n", "failed workflow runs", "your n8n → Settings → API"],
                        ["anthropic", "Claude API", "chat with Claude on your own key", "console.anthropic.com/settings/keys"],
                        ["openai", "OpenAI", "chat with OpenAI models on your own key", "platform.openai.com/api-keys"],
                        ["google", "Google AI", "chat with Gemini on your own key", "aistudio.google.com/apikey"]
                    ]

                    ColumnLayout {
                        id: integ

                        required property var modelData
                        readonly property bool has: !!App.keysSet[modelData[0]]

                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: integ.modelData[1]
                                color: Theme.text
                                font.pixelSize: 13
                            }
                            Text {
                                Layout.fillWidth: true
                                text: integ.has ? "connected" : integ.modelData[2]
                                color: integ.has ? App.cfg.color : Theme.faint
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            Link {
                                visible: integ.has
                                text: "remove"
                                onClicked: App.removeKey(integ.modelData[0])
                            }
                        }
                        // n8n runs on your own server: it needs its address too
                        KeyField {
                            visible: integ.modelData[0] === "n8n" && !App.keysSet["n8n-url"]
                            hint: "your n8n address, e.g. https://n8n.example.com"
                            secret: false
                            onSaved: v => App.saveKey("n8n-url", v)
                        }
                        KeyField {
                            visible: !integ.has
                            hint: `key from ${integ.modelData[3]}`
                            onSaved: v => App.saveKey(integ.modelData[0], v)
                        }
                    }
                }
            }

            // ---- plugins ----
            Section {
                visible: (win.st.plugins ?? []).length > 0
                text: "Plugins"
            }

            Card {
                visible: (win.st.plugins ?? []).length > 0

                Repeater {
                    model: win.st.plugins ?? []

                    Toggle {
                        required property var modelData

                        text: modelData.name ?? modelData.id
                        hint: modelData.error ? "can't be read" : (modelData.description ?? "")
                        checked: (App.cfg.plugins ?? []).includes(modelData.id)
                        enabled: !modelData.error
                        onToggled: on => {
                            const now = (App.cfg.plugins ?? []).filter(x => x !== modelData.id);
                            App.setCfg({ plugins: on ? now.concat([modelData.id]) : now });
                        }
                    }
                }
            }

            RowLayout {
                Layout.topMargin: 2

                Link {
                    text: "plugins folder"
                    onClicked: win.openPath(App.configPath.replace(/config\.json$/, "plugins"))
                }
                Link {
                    Layout.leftMargin: 12
                    text: "settings file"
                    onClicked: win.openPath(App.configPath)
                }
                Link {
                    Layout.leftMargin: 12
                    text: "help and source"
                    onClicked: Qt.openUrlExternally("https://github.com/teslaoruz/emba")
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    function openPath(p) {
        Qt.openUrlExternally(p.startsWith("/") ? `file://${p}` : `file:///${p.replace(/\\/g, "/")}`);
    }

    // ================================================================ parts

    component Link: Text {
        id: link

        signal clicked

        color: lh.hovered ? Theme.text : Theme.dim
        font.pixelSize: 11
        font.underline: lh.hovered

        HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: link.clicked() }
    }

    // a shell command with a Copy button
    component Command: Rectangle {
        id: cmd

        property string text

        Layout.fillWidth: true
        implicitHeight: 32
        radius: 8
        color: Qt.alpha(Theme.text, 0.06)

        TextInput {
            id: cmdText

            anchors.left: parent.left
            anchors.right: copyBtn.left
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: cmd.text
            readOnly: true
            selectByMouse: true
            clip: true
            autoScroll: false  // show the start of a long command, not its end
            color: Theme.text
            font.family: Qt.platform.os === "windows" ? "Consolas" : Qt.platform.os === "osx" ? "Menlo" : "monospace"
            font.pixelSize: 11
        }
        Link {
            id: copyBtn

            property bool done: false

            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: done ? "copied" : "copy"
            onClicked: {
                cmdText.selectAll();
                cmdText.copy();
                cmdText.deselect();
                done = true;
            }
        }
    }

    // a one-line field for a key: hidden as you type, saved on Enter, then cleared
    component KeyField: Rectangle {
        id: kf

        property string hint
        property bool secret: true
        signal saved(string value)

        Layout.fillWidth: true
        implicitHeight: 30
        radius: 8
        color: Qt.alpha(Theme.text, 0.06)

        TextInput {
            id: kfInput

            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            echoMode: kf.secret ? TextInput.Password : TextInput.Normal
            color: Theme.text
            font.pixelSize: 12
            clip: true
            onAccepted: if (text.trim()) {
                kf.saved(text);
                text = "";
            }

            Text {
                visible: !kfInput.text
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                text: kf.hint + " · Enter to save"
                color: Theme.faint
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }

    component Section: Text {
        Layout.topMargin: 6
        color: Theme.dim
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
    }

    component Card: Rectangle {
        default property alias content: inner.data

        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + 28
        radius: 16
        color: Theme.surface
        border.width: 1
        border.color: Qt.alpha(Theme.text, 0.05)

        ColumnLayout {
            id: inner

            x: 14
            y: 14
            width: parent.width - 28
            spacing: 12
        }
    }

    component Labelled: RowLayout {
        property string text
        default property alias content: slot.data

        Layout.fillWidth: true
        spacing: 10

        Text {
            Layout.preferredWidth: 58
            text: parent.text
            color: Theme.text
            font.pixelSize: 12
        }
        Row {
            id: slot

            Layout.fillWidth: true
        }
    }

    component Button: Rectangle {
        id: btn

        property string text
        property bool primary
        signal clicked

        implicitWidth: label.implicitWidth + 26
        implicitHeight: 30
        radius: 15
        color: primary ? (bh.hovered ? Qt.lighter(Theme.primary, 1.08) : Theme.primary) : Qt.alpha(Theme.text, bh.hovered ? 0.15 : 0.09)
        scale: bt.pressed ? 0.94 : 1

        Behavior on scale { NumberAnimation { duration: 90 } }

        Text {
            id: label

            anchors.centerIn: parent
            text: btn.text
            color: btn.primary ? Theme.onPrimary : Theme.text
            font.pixelSize: 12
            font.weight: Font.Medium
        }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: bt; onTapped: btn.clicked() }
    }

    component Toggle: Item {
        id: tg

        property string text
        property string hint
        property bool checked
        // an agent's colour beside its name; indent for a switch that belongs to the one above
        property color dot: "transparent"
        property bool indent: false
        signal toggled(bool on)

        Layout.fillWidth: true
        Layout.leftMargin: indent ? 16 : 0
        implicitHeight: Math.max(labels.implicitHeight, 22)
        opacity: enabled ? 1 : 0.5

        Rectangle {
            id: dotMark

            visible: tg.dot.a > 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? 8 : 0
            height: 8
            radius: 4
            color: tg.dot
        }
        Column {
            id: labels

            anchors.left: dotMark.right
            anchors.leftMargin: dotMark.visible ? 8 : 0
            anchors.right: knob.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: tg.text
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                visible: tg.hint !== ""
                text: tg.hint
                color: Theme.faint
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }
        Rectangle {
            id: knob

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            height: 22
            radius: 11
            color: tg.checked ? App.cfg.color : Qt.alpha(Theme.text, 0.15)

            Behavior on color { ColorAnimation { duration: 160 } }

            Rectangle {
                x: tg.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: "white"

                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler {
                enabled: tg.enabled
                onTapped: tg.toggled(!tg.checked)
            }
        }
    }

    component Segmented: Flow {
        id: seg

        property var options: []
        property var value
        signal picked(var v)

        width: parent ? parent.width : 200
        spacing: 4

        Repeater {
            model: seg.options

            Rectangle {
                required property var modelData
                readonly property bool on: seg.value === modelData[1]

                implicitWidth: segLabel.implicitWidth + 18
                implicitHeight: 26
                radius: 13
                color: on ? App.cfg.color : Qt.alpha(Theme.text, sh.hovered ? 0.12 : 0.06)

                Behavior on color { ColorAnimation { duration: 140 } }

                Text {
                    id: segLabel

                    anchors.centerIn: parent
                    text: parent.modelData[0]
                    color: parent.on ? "white" : Theme.text
                    font.pixelSize: 11
                    font.weight: parent.on ? Font.DemiBold : Font.Normal
                }
                HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: seg.picked(parent.modelData[1]) }
            }
        }
    }
}
