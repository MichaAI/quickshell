import QtQuick
import Quickshell
import "../config"

// Пузырёк со значением над ручкой слайдера (value indicator из MD3
// Expressive): выскакивает из ручки, пока её тянут. Живёт в отдельном
// всплывающем окне над слайдером, чтобы не упираться в край попаута;
// клики проходят сквозь него.
PopupWindow {
    id: root

    property Item target            // слайдер
    property real handleX: 0        // центр ручки, в координатах target
    property real handleTop: 0      // верх ручки, в координатах target
    property bool shown: false
    property string text: ""

    readonly property int pad: 40   // запас по бокам: пузырёк у края не обрезается

    anchor.item: target // qmllint disable missing-property
    anchor.rect.x: -pad // qmllint disable unqualified unresolved-type
    anchor.rect.y: handleTop
    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: Edges.Top | Edges.Left // qmllint disable missing-property
    anchor.gravity: Edges.Top | Edges.Right // qmllint disable missing-property
    // Не двигать окно от края экрана: иначе пузырёк съедет с ручки
    anchor.adjustment: PopupAdjustment.None // qmllint disable missing-property
    implicitWidth: (target?.width ?? 0) + 2 * pad
    implicitHeight: 12 + 30 + 6
    color: "transparent"
    mask: Region {}
    visible: shown || bubble.scale > 0.01

    Rectangle {
        id: bubble
        x: root.handleX + root.pad - width / 2
        // 12 px над ручкой — ValueIndicatorActiveBottomSpace
        y: root.implicitHeight - 12 - height
        width: Math.max(height, label.implicitWidth + 20)
        height: 30
        radius: height / 2
        color: Theme.text
        transformOrigin: Item.Bottom
        scale: root.shown ? 1 : 0
        Behavior on scale { Spring { epsilon: 0.002 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Theme.crust
        }
    }
}
