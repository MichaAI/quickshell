pragma ComponentBehavior: Bound
import QtQuick
import "../config"

// Фильтр-чипы MD3 Expressive, сколько влезет в строку. Выбранный чип
// заливается, из квадратного (углы 8) становится пилюлей и выпускает
// галочку — всё пружиной.
//
// options — [{id, label}]. Одиночный выбор: current — id; multi: current —
// массив id. Значение не меняет сам: шлёт picked, current задаёт хозяин.
// shake() — встряхнуть при откате
Item {
    id: root

    property var options: []
    property var current
    property bool multi: false
    signal picked(string id)

    implicitWidth: flow.implicitWidth
    implicitHeight: flow.implicitHeight

    property real shakeX: 0
    transform: Translate { x: root.shakeX }
    SpringAnimation {
        id: shakeAnim
        target: root; property: "shakeX"; to: 0
        spring: Motion.shakeSpring; damping: Motion.shakeDamping; epsilon: 0.2
    }
    function shake() {
        shakeX = 8
        shakeAnim.restart()
    }

    Flow {
        id: flow
        width: root.width
        spacing: 8

        // Наведение — один обработчик на все чипы, чип сверяет с ним свою
        // геометрию: у выбранного меняется ширина, соседи едут, и свой
        // ховер у каждого залипал бы
        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }

        Repeater {
            model: root.options

            Rectangle {
                id: chip
                required property var modelData

                readonly property bool sel: root.multi ? (root.current ?? []).includes(modelData.id)
                                                       : modelData.id === root.current

                readonly property bool hot: hover.hovered
                    && hover.point.position.x >= x && hover.point.position.x < x + width
                    && hover.point.position.y >= y && hover.point.position.y < y + height

                width: content.implicitWidth + 24
                height: 32
                radius: sel ? 16 : 8
                Behavior on radius { Spring {} }
                Behavior on width { Spring {} }
                color: sel ? Theme.alpha(Theme.gradEnd, 0.22)
                     : hot ? Theme.surface0 : "transparent"
                border.width: sel ? 0 : 1
                border.color: Theme.surface2
                Behavior on color { ColorAnimation { duration: 120 } }

                scale: press.pressed ? 0.95 : 1
                Behavior on scale { Spring { epsilon: 0.002 } }

                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: chip.sel ? 6 : 0

                    Item {
                        width: chip.sel ? check.implicitWidth : 0
                        height: check.implicitHeight
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on width { Spring {} }

                        Text {
                            id: check
                            text: "󰄬"
                            font.family: Theme.font
                            font.pixelSize: 14
                            color: Theme.gradEnd
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.label
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: chip.sel ? Theme.text : Theme.subtext0
                    }
                }

                MouseArea {
                    id: press
                    anchors.fill: parent
                    onClicked: root.picked(chip.modelData.id)
                }
            }
        }
    }
}
