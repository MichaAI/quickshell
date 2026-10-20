pragma ComponentBehavior: Bound
import QtQuick
import "../config"

// Переключатель MD3 Expressive: дорожка 52×32, ручка 16 → 24, когда
// включён, и 28, пока нажата; едет пружиной. Значение не меняет сам —
// шлёт toggled, а checked задаёт хозяин. shake() — встряхнуть, если
// настройка не применилась и значение откатилось
Item {
    id: root

    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 52
    implicitHeight: 32
    opacity: enabled ? 1 : 0.38

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

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.surface0
        border.width: 2
        border.color: root.checked ? "transparent" : Theme.overlay0
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            opacity: root.checked ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            gradient: OkGradient {
                orientation: Gradient.Horizontal
                from: Theme.gradStart
                to: Theme.gradEnd
            }
        }
    }

    Rectangle {
        id: handle
        property real size: mouse.pressed ? 28 : root.checked ? 24 : 16
        Behavior on size { Spring {} }
        // Центр ручки — в 16 px от своего края дорожки
        x: (root.checked ? root.width - 16 : 16) - size / 2
        Behavior on x { Spring {} }
        anchors.verticalCenter: parent.verticalCenter
        width: size
        height: size
        radius: size / 2
        color: root.checked ? Theme.crust : Theme.overlay1
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "󰄬"
            font.family: Theme.font
            font.pixelSize: 14
            color: Theme.gradStart
            opacity: root.checked ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
