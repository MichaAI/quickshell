import QtQuick
import "../config"

// Ползунок с произвольной градиентной полосой (яркость, прозрачность…).
Item {
    id: root

    property real value: 0          // 0..1
    property color from: "black"
    property color to: "white"
    property string label: ""
    property bool checker: false    // шахматка под полосой — для прозрачности

    signal moved(real value)

    implicitHeight: 18
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
        height: 12

        Item {
            anchors.fill: parent
            visible: root.checker
            clip: true
            layer.enabled: true

            Row {
                Repeater {
                    model: Math.max(0, Math.ceil(track.width / 6))
                    Column {
                        required property int index
                        Rectangle { width: 6; height: 6; color: parent.index % 2 ? Theme.surface1 : Theme.overlay0 }
                        Rectangle { width: 6; height: 6; color: parent.index % 2 ? Theme.overlay0 : Theme.surface1 }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 6
            border.width: 1
            border.color: Theme.surface0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.from }
                GradientStop { position: 1; color: root.to }
            }
        }

        // Скругляем шахматку рамкой цвета фона
        Rectangle {
            visible: root.checker
            anchors.fill: parent
            anchors.margins: -4
            radius: 10
            color: "transparent"
            border.width: 4
            border.color: Theme.popoutBg
        }

        Rectangle {
            x: Math.max(0, Math.min(track.width, root.value * track.width)) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: Theme.text
            border.color: Theme.crust
            border.width: 3
            scale: mouse.containsMouse || mouse.pressed ? 1.15 : 1
            Behavior on scale { Spring { epsilon: 0.002 } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: track
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function report(mx) {
            root.moved(Math.max(0, Math.min(1, (mx - 4) / track.width)))
        }

        onPressed: e => report(e.x)
        onPositionChanged: e => { if (pressed) report(e.x) }
        onWheel: e => root.moved(Math.max(0, Math.min(1, root.value + (e.angleDelta.y > 0 ? 0.02 : -0.02))))
    }
}
