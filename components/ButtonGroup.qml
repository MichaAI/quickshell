pragma ComponentBehavior: Bound
import QtQuick
import "../config"

// Группа соединённых кнопок MD3 Expressive (connected button group):
// кнопки стоят встык, внутренние углы маленькие, внешние — круглые.
// Выбранная становится пилюлей целиком, шире соседей и залита градиентом;
// углы и ширины перетекают пружиной.
//
// options — [{id, label, icon?}]. Если tall и у вариантов есть значки —
// значок над подписью. Значение не меняет сам: шлёт picked, current задаёт
// хозяин. shake() — встряхнуть при откате
Item {
    id: root

    property var options: []
    property var current
    property bool tall: false
    signal picked(string id)

    implicitWidth: 300
    implicitHeight: tall ? 64 : 40

    readonly property int gap: 2
    readonly property real grow: 1.3
    readonly property bool hasCurrent: options.some(o => o.id === current)
    readonly property real weights: options.length - (hasCurrent ? 1 : 0) + (hasCurrent ? grow : 0)

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

    Row {
        spacing: root.gap

        // Наведение — один обработчик на всю группу, кнопка сверяет с ним
        // свою геометрию. Свой ховер у каждой кнопки залипал: после клика
        // ширины пружинят, кнопка уезжает из-под курсора, а Qt пересчитывает
        // наведение только при движении мыши
        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }

        Repeater {
            model: root.options

            Item {
                id: seg
                required property var modelData
                required property int index

                readonly property bool sel: modelData.id === root.current
                readonly property bool first: index === 0
                readonly property bool last: index === root.options.length - 1
                readonly property real outer: height / 2
                readonly property real inner: sel ? height / 2 : 8

                width: Math.max(0, (root.width - root.gap * (root.options.length - 1))
                    * (sel ? root.grow : 1) / Math.max(1, root.weights))
                height: root.height
                Behavior on width { Spring {} }

                readonly property bool hot: hover.hovered && hover.point.position.x >= x
                    && hover.point.position.x < x + width

                scale: press.pressed ? 0.96 : 1
                Behavior on scale { Spring { epsilon: 0.002 } }

                component Shape: Rectangle {
                    anchors.fill: parent
                    topLeftRadius: seg.first ? seg.outer : seg.inner
                    bottomLeftRadius: seg.first ? seg.outer : seg.inner
                    topRightRadius: seg.last ? seg.outer : seg.inner
                    bottomRightRadius: seg.last ? seg.outer : seg.inner
                    Behavior on topLeftRadius { Spring {} }
                    Behavior on bottomLeftRadius { Spring {} }
                    Behavior on topRightRadius { Spring {} }
                    Behavior on bottomRightRadius { Spring {} }
                }

                Shape {
                    color: seg.hot && !seg.sel ? Theme.surface1 : Theme.surface0
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                Shape {
                    opacity: seg.sel ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    gradient: OkGradient {
                        orientation: Gradient.Horizontal
                        from: Theme.gradStart
                        to: Theme.gradEnd
                    }
                }

                Grid {
                    anchors.centerIn: parent
                    columns: root.tall ? 1 : 2
                    columnSpacing: 6
                    rowSpacing: 2
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter

                    Text {
                        visible: (seg.modelData.icon ?? "") !== ""
                        text: seg.modelData.icon ?? ""
                        font.family: Theme.font
                        font.pixelSize: root.tall ? 20 : 15
                        color: seg.sel ? Theme.crust : Theme.subtext1
                    }
                    Text {
                        text: seg.modelData.label
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: seg.sel ? Font.DemiBold : Font.Normal
                        color: seg.sel ? Theme.crust : Theme.subtext1
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, seg.width - 12)
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                MouseArea {
                    id: press
                    anchors.fill: parent
                    onClicked: if (!seg.sel) root.picked(seg.modelData.id)
                }
            }
        }
    }
}
