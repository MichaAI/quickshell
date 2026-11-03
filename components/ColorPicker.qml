pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../config"
import "Colors.js" as Colors

// Полноценный выбор цвета: колесо оттенок/насыщенность, яркость, прозрачность,
// превью и список форматов (клик — скопировать).
Item {
    id: root

    // Текущий цвет в HSV + альфа (0..1)
    property real h: 0
    property real s: 0
    property real v: 1
    property real a: 1

    property int selFormat: 0

    readonly property var rgba: {
        const c = Colors.fromHsv(h, s, v)
        c.a = a
        return c
    }
    readonly property var formats: Colors.formats(rgba)
    readonly property color qcolor: Qt.rgba(rgba.r, rgba.g, rgba.b, rgba.a)

    // Цвет поменяли мышью (не через setColor)
    signal edited()
    signal copyRequested(string text)
    signal pickRequested()

    function setColor(c) {
        const x = Colors.toHsv(c)
        // У серых оттенок не определён — оставляем прежний, чтобы колесо не прыгало
        if (x.s > 0 && x.v > 0) h = x.h
        if (x.v > 0) s = x.s
        v = x.v
        a = c.a ?? 1
    }

    function move(d) {
        selFormat = (selFormat + d + formats.length) % formats.length
    }

    function activate() {
        copyRequested(formats[selFormat][1])
    }

    // Стрелки с Ctrl/Shift: оттенок, насыщенность, яркость
    function nudge(dh, ds, dv) {
        h = ((h + dh) % 1 + 1) % 1
        s = Colors.clamp(s + ds, 0, 1)
        v = Colors.clamp(v + dv, 0, 1)
        edited()
    }

    implicitWidth: 592
    implicitHeight: 330

    // ===== Колесо =====
    Item {
        id: wheelBox
        width: 230
        height: 230
        anchors.left: parent.left
        anchors.top: parent.top

        // Оттенок — коническим градиентом (он идёт против часовой, а угол
        // у нас по часовой — отсюда 1 - позиция), насыщенность — белым к центру
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillGradient: ConicalGradient {
                    centerX: wheelBox.width / 2
                    centerY: wheelBox.height / 2
                    angle: 0
                    GradientStop { position: 0 / 6; color: Qt.hsva(0 / 6, 1, 1, 1) }
                    GradientStop { position: 1 / 6; color: Qt.hsva(5 / 6, 1, 1, 1) }
                    GradientStop { position: 2 / 6; color: Qt.hsva(4 / 6, 1, 1, 1) }
                    GradientStop { position: 3 / 6; color: Qt.hsva(3 / 6, 1, 1, 1) }
                    GradientStop { position: 4 / 6; color: Qt.hsva(2 / 6, 1, 1, 1) }
                    GradientStop { position: 5 / 6; color: Qt.hsva(1 / 6, 1, 1, 1) }
                    GradientStop { position: 6 / 6; color: Qt.hsva(0 / 6, 1, 1, 1) }
                }
                PathAngleArc {
                    centerX: wheelBox.width / 2
                    centerY: wheelBox.height / 2
                    radiusX: wheelBox.width / 2
                    radiusY: wheelBox.height / 2
                    startAngle: 0
                    sweepAngle: 360
                }
            }

            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: wheelBox.width / 2
                    centerY: wheelBox.height / 2
                    focalX: centerX
                    focalY: centerY
                    centerRadius: wheelBox.width / 2
                    focalRadius: 0
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 1) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                }
                PathAngleArc {
                    centerX: wheelBox.width / 2
                    centerY: wheelBox.height / 2
                    radiusX: wheelBox.width / 2
                    radiusY: wheelBox.height / 2
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }

        // Яркость — затемнением поверх колеса
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "black"
            opacity: 1 - root.v
        }

        // Маркер
        Rectangle {
            readonly property real r: root.s * wheelBox.width / 2
            readonly property real ang: root.h * 2 * Math.PI
            x: wheelBox.width / 2 + Math.cos(ang) * r - width / 2
            y: wheelBox.height / 2 + Math.sin(ang) * r - height / 2
            width: 18
            height: 18
            radius: 9
            color: Qt.rgba(root.rgba.r, root.rgba.g, root.rgba.b, 1)
            border.width: 3
            border.color: "white"

            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Theme.crust
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.CrossCursor

            function report(mx, my) {
                const R = wheelBox.width / 2
                const dx = mx - R, dy = my - R
                root.h = (Math.atan2(dy, dx) / (2 * Math.PI) + 1) % 1
                root.s = Math.min(1, Math.sqrt(dx * dx + dy * dy) / R)
                root.edited()
            }

            onPressed: e => report(e.x, e.y)
            onPositionChanged: e => { if (pressed) report(e.x, e.y) }
            onWheel: e => root.nudge(e.angleDelta.y > 0 ? 0.01 : -0.01, 0, 0)
        }
    }

    // ===== Справа: превью, ползунки, форматы =====
    Column {
        anchors.left: wheelBox.right
        anchors.leftMargin: 22
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 12

        Row {
            width: parent.width
            spacing: 12

            // Превью поверх шахматки (видно прозрачность)
            Item {
                width: 96
                height: 64

                Grid {
                    anchors.fill: parent
                    columns: 12
                    clip: true
                    Repeater {
                        model: 12 * 8
                        Rectangle {
                            required property int index
                            width: 8
                            height: 8
                            color: (index + Math.floor(index / 12)) % 2 ? Theme.surface1 : Theme.overlay0
                        }
                    }
                    layer.enabled: true
                }
                Rectangle {
                    anchors.fill: parent
                    color: root.qcolor
                }
                // Скругление поверх шахматки — рамкой цвета фона
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -6
                    radius: 16
                    color: "transparent"
                    border.width: 6
                    border.color: Theme.popoutBg
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    text: root.formats[0][1]
                    font.family: Theme.font
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    color: Theme.text
                }
                Text {
                    text: "󰈊 пипетка"
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: pickMouse.containsMouse ? Theme.mauve : Theme.overlay1

                    MouseArea {
                        id: pickMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pickRequested()
                    }
                }
            }
        }

        // Яркость
        GradientSlider {
            width: parent.width
            label: "󰃟"
            value: root.v
            from: "black"
            to: { const c = Colors.fromHsv(root.h, root.s, 1); return Qt.rgba(c.r, c.g, c.b, 1) }
            onMoved: val => { root.v = val; root.edited() }
        }

        // Прозрачность
        GradientSlider {
            width: parent.width
            label: "󰂵"
            checker: true
            value: root.a
            from: Qt.rgba(root.rgba.r, root.rgba.g, root.rgba.b, 0)
            to: Qt.rgba(root.rgba.r, root.rgba.g, root.rgba.b, 1)
            onMoved: val => { root.a = val; root.edited() }
        }

        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: root.formats

                Rectangle {
                    id: fmt
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.selFormat

                    width: parent.width
                    height: 30
                    radius: 8
                    color: selected ? Theme.cardBg
                         : fmtMouse.containsMouse ? Theme.alpha(Theme.cardBg, 0.5) : "transparent"

                    Rectangle {
                        visible: fmt.selected
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 16
                        radius: 2
                        gradient: OkGradient {
                            from: Theme.gradStart
                            to: Theme.gradEnd
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        text: fmt.modelData[0]
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.overlay1
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 58
                        anchors.verticalCenter: parent.verticalCenter
                        text: fmt.modelData[1]
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: fmt.selected ? Theme.text : Theme.subtext0
                    }
                    Text {
                        visible: fmt.selected || fmtMouse.containsMouse
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰆏"
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.overlay1
                    }

                    MouseArea {
                        id: fmtMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selFormat = fmt.index
                            root.activate()
                        }
                    }
                }
            }
        }
    }
}
