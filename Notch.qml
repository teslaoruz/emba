import QtQuick
import QtQuick.Shapes

// The island's outline, drawn so it grows out of the screen's edge like a
// phone notch: corners on the screen edge are square, corners out in the
// open are rounded, and where the shape meets an edge it flares into it with
// a small inward curve ("ears") instead of a hard joint.
//
// Set `body` (the island's size) and which screen edges it touches; the item
// sizes itself to include the ears, and `bodyX`/`bodyY` say where the body sits.
Item {
    id: root

    property size body: Qt.size(100, 40)
    property bool atTop
    property bool atRight
    property bool atBottom
    property bool atLeft
    property real radius: 20
    property real ear: 14
    property color fill: "black"
    property color stroke: "transparent"
    property real strokeWidth: 0

    // room for ears that stick out past the body along an attached edge
    readonly property real ml: !atLeft && (atTop || atBottom) ? ear : 0
    readonly property real mr: !atRight && (atTop || atBottom) ? ear : 0
    readonly property real mt: !atTop && (atLeft || atRight) ? ear : 0
    readonly property real mb: !atBottom && (atLeft || atRight) ? ear : 0
    readonly property real bodyX: ml
    readonly property real bodyY: mt

    implicitWidth: body.width + ml + mr
    implicitHeight: body.height + mt + mb

    function outline() {
        const L = ml, T = mt, R = ml + body.width, B = mt + body.height;
        const r = Math.max(0, Math.min(radius, body.width / 2, body.height / 2));
        const e = Math.max(0, Math.min(ear, body.width / 2, body.height / 2));
        // clockwise: each corner knows the edge it arrives on and the one it leaves by
        const corners = [
            { x: L, y: T, inX: 0, inY: -1, outX: 1, outY: 0, prev: atLeft, next: atTop },
            { x: R, y: T, inX: 1, inY: 0, outX: 0, outY: 1, prev: atTop, next: atRight },
            { x: R, y: B, inX: 0, inY: 1, outX: -1, outY: 0, prev: atRight, next: atBottom },
            { x: L, y: B, inX: -1, inY: 0, outX: 0, outY: -1, prev: atBottom, next: atLeft }
        ];
        const ends = c => {
            if (c.prev && c.next)  // in the screen's corner: square
                return { a: [c.x, c.y], b: [c.x, c.y], arc: "" };
            if (!c.prev && !c.next)  // out in the open: rounded
                return { a: [c.x - c.inX * r, c.y - c.inY * r], b: [c.x + c.outX * r, c.y + c.outY * r], arc: `A ${r} ${r} 0 0 1` };
            // against one edge: flare into it
            const s = c.prev ? 1 : -1;
            return { a: [c.x + s * c.inX * e, c.y + s * c.inY * e], b: [c.x + s * c.outX * e, c.y + s * c.outY * e], arc: `A ${e} ${e} 0 0 0` };
        };
        const p = corners.map(ends);
        let d = `M ${p[0].b[0]} ${p[0].b[1]}`;
        for (const i of [1, 2, 3, 0]) {
            d += ` L ${p[i].a[0]} ${p[i].a[1]}`;
            if (p[i].arc)
                d += ` ${p[i].arc} ${p[i].b[0]} ${p[i].b[1]}`;
        }
        return d + " Z";
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.fill
            strokeColor: root.stroke
            strokeWidth: root.strokeWidth

            PathSvg {
                path: root.outline()
            }
        }
    }
}
