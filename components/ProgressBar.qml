import QtQuick
import "../config"

// Тонкая полоса прогресса в градиенте темы. value — доля 0…1;
// меньше нуля — «сколько всего, неизвестно»: бегущий отрезок.
Rectangle {
    id: track

    property real value: 0

    implicitHeight: 3
    radius: height / 2
    color: Theme.surface0
    clip: true

    Rectangle {
        visible: track.value >= 0
        height: parent.height
        radius: parent.radius
        width: parent.width * Math.max(0, Math.min(1, track.value))
        Behavior on width { NumberAnimation { duration: 250 } }
        gradient: OkGradient {
            orientation: Gradient.Horizontal
            from: Theme.gradStart
            to: Theme.gradEnd
        }
    }

    Rectangle {
        visible: track.value < 0
        height: parent.height
        radius: parent.radius
        width: parent.width * 0.25
        gradient: OkGradient {
            orientation: Gradient.Horizontal
            from: Theme.gradStart
            to: Theme.gradEnd
        }
        NumberAnimation on x {
            running: track.visible && track.value < 0
            loops: Animation.Infinite
            from: -track.width * 0.25
            to: track.width
            duration: 1200
            easing.type: Easing.InOutQuad
        }
    }
}
