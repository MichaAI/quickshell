import QtQuick
import QtQuick.Shapes
import "../config"

// Вогнутый ("внутренний") угол. Базовая ориентация — примыкает к верхнему
// и левому краям; right/bottom зеркалируют.
Shape {
    id: root

    property real radius: Settings.screenRadius
    property color col: Theme.barBg
    property bool flipX: false
    property bool flipY: false

    width: radius
    height: radius
    preferredRendererType: Shape.CurveRenderer

    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: root.flipX ? -1 : 1
        yScale: root.flipY ? -1 : 1
    }

    ShapePath {
        strokeWidth: -1
        fillColor: root.col
        startX: 0; startY: 0

        PathLine { x: 0; y: root.radius }
        PathArc {
            x: root.radius; y: 0
            radiusX: root.radius; radiusY: root.radius
        }
        PathLine { x: 0; y: 0 }
    }
}
