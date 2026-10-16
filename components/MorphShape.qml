import QtQuick
import "../config"

// Фигура с морфингом в шейдере (morph.frag): радиус от угла — лепестки
// поверх суперэллипса [лепестков, глубина, степень, вытянутость]; morph
// смешивает from → to, turn крутит. Настоящие MaterialShapes — в
// MaterialShape, здесь остался рабочий для рамки поля лока. Ещё умеет перетекать
// в скруглённый прямоугольник (box*) и истончаться до обводки (band), а
// снаружи — рамка outline цвета фона, чтобы отделить фигуру от подложки.
// reveal*: показать только круг вокруг точки (от центра item) — для
// «расползания» цвета. Фигура рисуется по центру, радиус — radius.
ShaderEffect {
    id: s

    property var from: [0, 0, 2, 1]
    property var to: [0, 0, 2, 1]
    property real morph: 0
    property real turn: 0
    property real radius: Math.min(width, height) / 2
    property real boxWidth: 0
    property real boxHeight: 0
    property real boxRadius: 0
    property real boxMix: 0
    property real band: 10000
    property real outline: 0
    property color outlineColor: Theme.crust
    property color colorFrom: Theme.gradStart
    property color colorTo: Theme.gradEnd
    property bool revealOn: false
    property real revealX: 0
    property real revealY: 0
    property real revealRadius: 0

    property size size: Qt.size(width, height)
    property vector4d shapeA: Qt.vector4d(from[0], from[1], from[2], from[3])
    property vector4d shapeB: Qt.vector4d(to[0], to[1], to[2], to[3])
    property vector4d box: Qt.vector4d(boxWidth / 2, boxHeight / 2, boxRadius, boxMix)
    property color c0: colorFrom
    property color c1: colorTo
    property vector4d reveal: Qt.vector4d(revealX, revealY, revealRadius, revealOn ? 1 : 0)
    fragmentShader: Qt.resolvedUrl("../assets/shaders/morph.frag.qsb")
}
