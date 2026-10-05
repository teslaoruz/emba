// GitHub, for the repositories your sessions run in: the latest CI run on the
// current branch and its pull request, and the pull requests waiting for your
// review. Emba fetches it in the background every minute (status.py, plugin.json
// "poll"); click a line to open it on GitHub.
import QtQuick

Column {
    id: gh

    property var app
    property var theme
    readonly property var info: app?.pluginData?.github ?? {}
    readonly property var repos: info.repos ?? []
    readonly property var reviews: info.reviews ?? []

    visible: repos.length > 0 || reviews.length > 0
    width: parent ? parent.width : 300
    spacing: 4

    // reviews waiting for you, all repositories together: one line
    Rectangle {
        visible: gh.reviews.length > 0
        width: gh.width
        height: 32
        radius: 12
        color: revh.hovered ? gh.theme.fillHover : gh.theme.fill

        Text {
            x: 12
            width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            text: gh.reviews.length === 1 ? `Review waiting: ${gh.reviews[0].title}` : `${gh.reviews.length} pull requests waiting for your review`
            color: gh.theme.text
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        HoverHandler { id: revh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Qt.openUrlExternally(gh.reviews.length === 1 ? gh.reviews[0].url : "https://github.com/pulls/review-requested") }
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
