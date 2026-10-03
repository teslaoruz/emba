// GitHub, for the repositories your sessions run in: the latest CI run on the
// current branch and its pull request. Uses the `gh` CLI you're logged in with;
// click a line to open it on GitHub. Refreshes every minute while it is shown.
import QtQuick
import Quickshell.Io

Column {
    id: gh

    property var app
    property var theme
    property var repos: []
    property var incoming: []

    readonly property string script: Qt.resolvedUrl("status.py").toString().replace(/^file:\/\//, "").replace(/^\/([A-Za-z]:)/, "$1")
    readonly property var dirs: [...new Set((app?.sessions ?? []).map(s => s.cwd).filter(d => d))]

    visible: repos.length > 0
    width: parent ? parent.width : 300
    spacing: 4

    function refresh() {
        if (!dirs.length || proc.running)
            return;
        incoming = [];
        proc.command = [app?.python ?? "python3", script].concat(dirs);
        proc.running = true;
    }
    // the last answer shows at once (the island rebuilds this panel each time it opens)
    onAppChanged: if (app?.pluginData?.github)
        repos = app.pluginData.github
    Component.onCompleted: refresh()
    onDirsChanged: refresh()

    Timer {
        running: gh.visible || gh.dirs.length > 0
        interval: 60000
        repeat: true
        onTriggered: gh.refresh()
    }

    Process {
        id: proc

        stdout: SplitParser {
            onRead: line => {
                try {
                    gh.incoming = gh.incoming.concat([JSON.parse(line)]);
                } catch (e) {}
            }
        }
        onExited: {
            gh.repos = gh.incoming;
            if (gh.app)
                gh.app.pluginData = Object.assign({}, gh.app.pluginData, {
                    github: gh.repos
                });
        }
    }

    Repeater {
        model: gh.repos

        Rectangle {
            id: row

            required property var modelData
            readonly property var ci: modelData.ci
            readonly property var pr: modelData.pr
            readonly property color ciColour: !ci ? gh.theme.faint : ci.state === "success" ? "#3ecf8e" : ["failure", "timed_out", "startup_failure"].includes(ci.state) ? "#ff453a" : "#f5b14c"

            width: gh.width
            height: 40
            radius: 12
            color: rh.hovered ? gh.theme.fillHover : gh.theme.fill

            // CI: a dot in its colour
            Rectangle {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: row.ciColour
            }
            Column {
                x: 28
                width: parent.width - 40
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: `${row.modelData.repo.split("/").pop()}  ·  ${row.modelData.branch}`
                    color: gh.theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: {
                        const ci = row.ci ? ({ success: "checks passed", failure: "checks failed", in_progress: "checks running", queued: "checks queued", cancelled: "checks cancelled" })[row.ci.state] ?? `checks: ${row.ci.state}` : "no checks";
                        const pr = row.pr ? `  ·  PR #${row.pr.number}${row.pr.review === "APPROVED" ? " approved" : row.pr.review === "CHANGES_REQUESTED" ? " needs changes" : row.pr.state === "MERGED" ? " merged" : ""}` : "";
                        return ci + pr;
                    }
                    color: gh.theme.dim
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
            HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
            // the pull request if there is one, else the CI run
            TapHandler { onTapped: Qt.openUrlExternally(row.pr?.url || row.ci?.url || `https://github.com/${row.modelData.repo}`) }
        }
    }
}
