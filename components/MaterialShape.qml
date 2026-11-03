import QtQuick
import QtQuick.Shapes
import "../config"
import "Shapes.js" as Shapes

// Фигура MD3 Expressive (MaterialShapes) с морфом, как Morph из androidx:
// углы формы from перетекают в углы формы to (Shapes.js). morph — 0 у from,
// 1 у to, turn крутит (в оборотах), radius — самый дальний край, px.
// Заливка — градиент colorFrom → colorTo слева направо, в OkLab; снаружи —
// рамка outline цвета outlineColor, чтобы отделить фигуру от подложки.
// Рисуется векторно (CurveRenderer), по центру item.
Item {
    id: s

    property var from: Shapes.circle
    property var to: Shapes.circle
    property real morph: 0
    property real turn: 0
    property real radius: Math.min(width, height) / 2
    property color colorFrom: Theme.gradStart
    property color colorTo: Theme.gradEnd
    property real outline: 0
    property color outlineColor: Theme.crust

    // Точек на контуре: хватает для гладкости при наших размерах
    readonly property int count: 160
    // Контур — без поворота: turn крутит сам Shape (rotation). Иначе на
    // каждом кадре вращения контур заново считался бы в JS и заново
    // триангулировался — открытый попаут музыки ел этим ~10% ядра
    readonly property var pts: {
        const p = Shapes.points(from, to, morph, 0, count)
        const cx = width / 2, cy = height / 2, out = []
        for (let k = 0; k < count; k++)
            out.push(Qt.point(cx + p[2 * k] * radius, cy + p[2 * k + 1] * radius))
        out.push(out[0])
        return out
    }

    // Градиент — в координатах повёрнутого Shape: концы крутим обратно,
    // чтобы на экране он оставался горизонтальным
    readonly property real _a: turn * 2 * Math.PI
    readonly property real _gx: radius * Math.cos(_a)
    readonly property real _gy: radius * Math.sin(_a)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: s.radius > 0.5
        rotation: s.turn * 360

        // Рамка — тот же контур, обведённый шире, под заливкой
        ShapePath {
            strokeWidth: s.outline > 0 ? 2 * s.outline : -1
            strokeColor: s.outline > 0 ? s.outlineColor : "transparent"
            fillColor: s.outline > 0 ? s.outlineColor : "transparent"
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: s.pts }
        }
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: s.width / 2 - s._gx; y1: s.height / 2 + s._gy
                x2: s.width / 2 + s._gx; y2: s.height / 2 - s._gy
                GradientStop { position: 0; color: s.colorFrom }
                GradientStop { position: 0.125; color: Theme.mix(s.colorFrom, s.colorTo, 0.125) }
                GradientStop { position: 0.25; color: Theme.mix(s.colorFrom, s.colorTo, 0.25) }
                GradientStop { position: 0.375; color: Theme.mix(s.colorFrom, s.colorTo, 0.375) }
                GradientStop { position: 0.5; color: Theme.mix(s.colorFrom, s.colorTo, 0.5) }
                GradientStop { position: 0.625; color: Theme.mix(s.colorFrom, s.colorTo, 0.625) }
                GradientStop { position: 0.75; color: Theme.mix(s.colorFrom, s.colorTo, 0.75) }
                GradientStop { position: 0.875; color: Theme.mix(s.colorFrom, s.colorTo, 0.875) }
                GradientStop { position: 1; color: s.colorTo }
            }
            PathPolyline { path: s.pts }
        }
    }
}
