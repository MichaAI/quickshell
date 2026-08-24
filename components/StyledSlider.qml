import QtQuick
import ".."

// Слайдер в едином стиле: градиентная полоса, круглая ручка, drag + wheel.
Item {
    id: root

    property real value: 0          // 0..1
    property bool enabled: true
    property real wheelStep: 0.05

    signal moved(real value)

    implicitHeight: 20
    implicitWidth: 160

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Theme.surface0
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(track.height, root.value * track.width)
        height: track.height
        radius: 3
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.gradStart }
            GradientStop { position: 1; color: Theme.gradEnd }
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(track.width - width, root.value * track.width - width / 2))
        width: 12
        height: 12
        radius: 6
        color: Theme.text
        border.color: Theme.crust
        border.width: 2
        scale: mouse.containsMouse || mouse.pressed ? 1.2 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor

        function report(mx) {
            root.moved(Math.max(0, Math.min(1, mx / track.width)))
        }

        onPressed: event => report(event.x)
        onPositionChanged: event => { if (pressed) report(event.x) }
        onWheel: wheel => {
            const d = wheel.angleDelta.y > 0 ? root.wheelStep : -root.wheelStep
            root.moved(Math.max(0, Math.min(1, root.value + d)))
        }
    }
}
