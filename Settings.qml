pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// The settings window: `emba settings`, the gear on the island, or the
// desktop entry. Every control writes straight to ~/.config/emba/config.json.
FloatingWindow {
    id: win

    title: "Emba"
    implicitWidth: 460
    implicitHeight: 680
    color: Theme.base

    onVisibleChanged: if (!visible)
        App.settingsOpen = false

    readonly property var st: App.status

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 40
        clip: true

        ColumnLayout {
            id: col

            x: 24
            y: 20
            width: parent.width - 48
            spacing: 14

            // ---- header ----
            RowLayout {
                spacing: 14

                Panda {
                    id: panda

                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 76
                    bodyColor: App.cfg.color
                    mood: !win.st.hooks ? "idle" : App.pending.length ? "waiting" : "idle"
                    Component.onCompleted: wave()
                }
                ColumnLayout {
                    spacing: 2

                    Text {
                        text: "Emba"
                        color: Theme.text
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "A red panda that keeps an eye on Claude Code"
                        color: Theme.dim
                        font.pixelSize: 12
                    }
                }
            }

            // ---- Claude Code ----
            Section { text: "Claude Code" }

            Card {
                RowLayout {
                    Layout.fillWidth: true

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: win.st.hooks ? Theme.ok : Theme.warn
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: win.st.hooks ? "Connected" : "Not connected yet"
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: win.st.hooks ? "Hooks are in ~/.claude/settings.json. Restart open sessions to pick them up." : "Adds Emba's hooks to ~/.claude/settings.json. A backup is kept; nothing else changes."
                            color: Theme.dim
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                    }
                    Button {
                        text: App.busy ? "…" : win.st.hooks ? "Disconnect" : "Connect"
                        primary: !win.st.hooks
                        onClicked: App.run(win.st.hooks ? ["disconnect"] : ["connect"])
                    }
                }

                Toggle {
                    text: "Show usage limits"
                    hint: "Reads them from your statusline; its output stays the same"
                    checked: !!win.st.statusline
                    enabled: !!win.st.hooks && !App.busy
                    onToggled: on => App.run(on ? ["connect", "--statusline"] : ["connect"])
                }
                Toggle {
                    text: "Start with my session"
                    hint: "systemd user service"
                    checked: !!win.st.autostart
                    enabled: !App.busy
                    onToggled: on => App.run(["autostart", on ? "on" : "off"])
                }
            }

            // ---- placement ----
            Section { text: "Where Emba sits" }

            Card {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18

                    // a little screen with nine spots
                    Rectangle {
                        width: 132
                        height: 84
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
                                    required property string modelData

                                    width: 40
                                    height: 24

                                    Rectangle {
                                        visible: parent.modelData !== ""
                                        anchors.centerIn: parent
                                        readonly property bool on: App.cfg.position === parent.modelData
                                        width: on ? 26 : 18
                                        height: on ? 12 : 8
                                        radius: height / 2
                                        color: on ? App.cfg.color : spotHover.hovered ? Theme.dim : Theme.faint

                                        Behavior on width { NumberAnimation { duration: 160 } }
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }
                                    HoverHandler {
                                        id: spotHover

                                        enabled: parent.modelData !== ""
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                    TapHandler {
                                        enabled: parent.modelData !== ""
                                        onTapped: App.setCfg({ position: parent.modelData })
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
                            text: "Screen"
                            Segmented {
                                options: [["First", ""]].concat(Quickshell.screens.map(s => [s.name, s.name]))
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
                Labelled {
                    text: "Colours"
                    Segmented {
                        options: [["Auto", "auto"], ["Caelestia", "caelestia"], ["pywal", "pywal"], ["Custom", "custom"], ["Built-in", "default"]]
                        value: App.cfg.theme
                        onPicked: v => App.setCfg({ theme: v })
                    }
                }
                Text {
                    text: `Using: ${Theme.source}` + (Theme.source === "default" && App.cfg.theme !== "default" ? "  (nothing found for that choice)" : "")
                    color: Theme.dim
                    font.pixelSize: 11
                }
                Labelled {
                    text: "Fur"
                    Row {
                        spacing: 8

                        Repeater {
                            model: ["#e2683c", "#c8503a", "#a8643c", "#e88a5b", "#d9a05b", "#8a6f5c"]

                            Rectangle {
                                required property string modelData

                                width: 24
                                height: 24
                                radius: 12
                                color: modelData
                                border.width: App.cfg.color === modelData ? 3 : 0
                                border.color: Theme.text

                                TapHandler { onTapped: App.setCfg({ color: parent.modelData }) }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }
            }

            // ---- behaviour ----
            Section { text: "Behaviour" }

            Card {
                Toggle {
                    text: "Open for permission requests"
                    checked: App.cfg.autoOpenOnPermission
                    onToggled: on => App.setCfg({ autoOpenOnPermission: on })
                }
                Toggle {
                    text: "Celebrate when a session finishes"
                    checked: App.cfg.celebrate
                    onToggled: on => App.setCfg({ celebrate: on })
                }
                Toggle {
                    text: "Hide while nothing is running"
                    hint: "leaves a small nub to hover"
                    checked: App.cfg.hideWhenIdle
                    onToggled: on => App.setCfg({ hideWhenIdle: on })
                }
                Toggle {
                    text: "Eyes follow the cursor"
                    hint: "Hyprland"
                    checked: App.cfg.trackCursor
                    onToggled: on => App.setCfg({ trackCursor: on })
                }
                Labelled {
                    text: "Usage warning"
                    Segmented {
                        options: [["70%", 70], ["80%", 80], ["90%", 90], ["Off", 101]]
                        value: App.cfg.limitWarn
                        onPicked: v => App.setCfg({ limitWarn: v })
                    }
                }
            }

            RowLayout {
                Layout.topMargin: 4

                Text {
                    text: "Open config file"
                    color: cfgHover.hovered ? Theme.text : Theme.dim
                    font.pixelSize: 11
                    font.underline: true

                    HoverHandler { id: cfgHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Quickshell.execDetached(["xdg-open", App.configPath]) }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "Not affiliated with Anthropic"
                    color: Theme.faint
                    font.pixelSize: 10
                }
            }
        }
    }

    // ================================================================ parts

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

    component Toggle: RowLayout {
        id: tg

        property string text
        property string hint
        property bool checked
        signal toggled(bool on)

        Layout.fillWidth: true
        opacity: enabled ? 1 : 0.5

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                text: tg.text
                color: Theme.text
                font.pixelSize: 12
            }
            Text {
                visible: tg.hint !== ""
                text: tg.hint
                color: Theme.faint
                font.pixelSize: 10
            }
        }
        Rectangle {
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
