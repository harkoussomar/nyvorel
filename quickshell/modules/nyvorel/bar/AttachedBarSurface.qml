pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property bool vertical: false
    property bool reverse: false
    property real inset: 18
    required property real cornerRadius
    required property color fillColor
    required property color strokeColor

    // Rotate the same open contour to meet any edge of the navbar.
    Shape {
        id: attachedSurface

        preferredRendererType: Shape.CurveRenderer
        transformOrigin: Item.TopLeft
        width: root.vertical ? root.height : root.width
        height: root.vertical ? root.width : root.height
        x: root.reverse ? root.width : 0
        y: root.reverse !== root.vertical
            ? root.height : 0
        rotation: root.vertical ? (root.reverse ? 90 : -90)
            : root.reverse ? 180 : 0

        // Keep the full stroke inside the exposed edge of the clip.
        readonly property real outerEdge: Math.max(0, height - 0.5)
        readonly property real shoulder: Math.min(root.inset, outerEdge / 3)
        readonly property real corner: Math.min(root.cornerRadius,
            root.inset, outerEdge / 4)
        readonly property real rightSide: width - shoulder

        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            strokeWidth: 1
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin
            startX: 0
            startY: 0

            PathArc {
                x: attachedSurface.shoulder
                y: attachedSurface.shoulder
                radiusX: attachedSurface.shoulder
                radiusY: attachedSurface.shoulder
                direction: PathArc.Clockwise
            }
            PathLine {
                x: attachedSurface.shoulder
                y: attachedSurface.outerEdge - attachedSurface.corner
            }
            PathArc {
                x: attachedSurface.shoulder + attachedSurface.corner
                y: attachedSurface.outerEdge
                radiusX: attachedSurface.corner
                radiusY: attachedSurface.corner
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: attachedSurface.rightSide - attachedSurface.corner
                y: attachedSurface.outerEdge
            }
            PathArc {
                x: attachedSurface.rightSide
                y: attachedSurface.outerEdge - attachedSurface.corner
                radiusX: attachedSurface.corner
                radiusY: attachedSurface.corner
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: attachedSurface.rightSide
                y: attachedSurface.shoulder
            }
            PathArc {
                x: attachedSurface.width
                y: 0
                radiusX: attachedSurface.shoulder
                radiusY: attachedSurface.shoulder
                direction: PathArc.Clockwise
            }
        }
    }
}
