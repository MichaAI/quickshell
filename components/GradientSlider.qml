import QtQuick
import QtQuick.Effects
import "../config"

// Ползунок с произвольной градиентной полосой (яркость, прозрачность…).
// Стиль и толщина — как у StyledSlider (Settings.sliderStyle, sliderSize):
// expressive — две части дорожки и ручка-палочка с зазором; pill — сплошная
// пилюля и круглая ручка внутри. Градиент — в sRGB, а не в OkLab: полоса
// обязана показывать ровно те цвета, что выберет пипетка.
Item {
    id: root

    property real value: 0          // 0..1
    property color from: "black"
    property color to: "white"
    property string label: ""
    property bool checker: false    // шахматка под полосой — для прозрачности

    signal moved(real value)

    readonly property bool pill: Settings.sliderStyle === "pill"
    readonly property real handleH: pill ? Theme.sliderSpec[0] : Theme.sliderSpec[2]

    implicitHeight: handleH
    implicitWidth: 200

    Text {
        id: icon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.label !== "" ? 22 : 0
        text: root.label
        font.family: Theme.font
        font.pixelSize: 14
        color: Theme.overlay1
    }

    Item {
        id: track
        anchors.left: icon.right
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.sliderSpec[0]

        readonly property real outer: root.pill ? height / 2 : Math.min(Theme.sliderSpec[1], height / 2)
        readonly property real gap: 6
        readonly property real v: Math.max(0, Math.min(1, root.value))
        // Центр ручки: у pill — центр круга, иначе палочка 4 px
        readonly property real cx: root.pill ? height / 2 + v * (width - height) : 2 + v * (width - 4)
        readonly property real leftEnd: root.pill ? width : cx - 2 - gap
        readonly property real rightStart: cx + 2 + gap

        // Цвет полосы в точке x, линейно по sRGB
        function at(x) {
            const t = Math.max(0, Math.min(1, (x - 2) / (width - 4)))
            const a = root.from, b = root.to
            return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                           a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
        }

        // Шахматка под прозрачностью, вырезанная по форме частей дорожки
        Item {
            id: checkerSrc
            anchors.fill: parent
            visible: false
            clip: true
            layer.enabled: true

            Grid {
                id: cells
                columns: Math.max(1, Math.ceil(track.width / 8))
                Repeater {
                    // Шахматный порядок: true — светлая клетка
                    model: {
                        const n = cells.columns, light = []
                        for (let i = 0; i < n * Math.ceil(track.height / 8); i++)
                            light.push((i % n + Math.floor(i / n)) % 2 === 1)
                        return light
                    }
                    Rectangle {
                        required property bool modelData
                        width: 8
                        height: 8
                        color: modelData ? Theme.surface1 : Theme.overlay0
                    }
                }
            }
        }

        Item {
            id: checkerMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Repeater {
                model: [lead, trail]
                Rectangle {
                    required property Rectangle modelData
                    visible: modelData.visible
                    x: modelData.x
                    width: modelData.width
                    height: modelData.height
                    topLeftRadius: modelData.topLeftRadius
                    bottomLeftRadius: modelData.bottomLeftRadius
                    topRightRadius: modelData.topRightRadius
                    bottomRightRadius: modelData.bottomRightRadius
                }
            }
        }
        MultiEffect {
            visible: root.checker
            anchors.fill: parent
            source: checkerSrc
            maskEnabled: true
            maskSource: checkerMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        component Part: Rectangle {
            id: part
            property real outer: 8
            property bool leading: true
            property bool trailing: true
            property color c0
            property color c1
            visible: width > 0
            topLeftRadius: leading ? outer : 2
            bottomLeftRadius: leading ? outer : 2
            topRightRadius: trailing ? outer : 2
            bottomRightRadius: trailing ? outer : 2
            border.width: 1
            border.color: Theme.surface0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: part.c0 }
                GradientStop { position: 1; color: part.c1 }
            }
        }

        Part {
            id: lead
            outer: track.outer
            trailing: root.pill
            width: Math.max(0, track.leftEnd)
            height: track.height
            c0: track.at(0)
            c1: track.at(lead.width)
        }
        Part {
            id: trail
            visible: !root.pill && width > 0
            outer: track.outer
            leading: false
            x: track.rightStart
            width: Math.max(0, track.width - track.rightStart)
            height: track.height
            c0: track.at(track.rightStart)
            c1: track.at(track.width)
        }

        // Ручка expressive: палочка, на нажатии худеет до 2 px
        Rectangle {
            visible: !root.pill
            x: track.cx - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: mouse.pressed ? 2 : 4
            height: root.handleH
            radius: width / 2
            color: Theme.text
            Behavior on width { NumberAnimation { duration: 100 } }
        }

        // Ручка pill: круг выбранного цвета в кольце
        Rectangle {
            visible: root.pill
            x: track.cx - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: track.height - 4
            height: width
            radius: width / 2
            color: track.at(track.cx)
            border.width: 2
            border.color: Theme.text
            scale: mouse.pressed ? 0.85 : 1
            Behavior on scale { Spring { epsilon: 0.002 } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: track
        anchors.topMargin: -(root.handleH - track.height) / 2 - 4
        anchors.bottomMargin: -(root.handleH - track.height) / 2 - 4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function report(mx) {
            const v = root.pill ? (mx - track.height / 2) / (track.width - track.height)
                                : (mx - 2) / (track.width - 4)
            root.moved(Math.max(0, Math.min(1, v)))
        }

        onPressed: e => report(e.x)
        onPositionChanged: e => { if (pressed) report(e.x) }
        onWheel: e => root.moved(Math.max(0, Math.min(1, root.value + (e.angleDelta.y > 0 ? 0.02 : -0.02))))
    }
}
