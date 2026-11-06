pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"
import "../components"

// Предупреждение перед локом по простою: экран плавно темнеет, по центру
// — сколько осталось. Ввод проходит насквозь: любое движение отменяет
// простой, и затемнение уходит.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow { // qmllint disable uncreatable-type
            id: warnWin
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:idle-warning"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            visible: Idle.warning || dim.opacity > 0

            property real startedAt: 0
            property real left: Idle.warnSec
            Connections {
                target: Idle
                function onWarningChanged() {
                    if (Idle.warning) {
                        warnWin.startedAt = Date.now()
                        warnWin.left = Idle.warnSec
                    }
                    // Параметры задаём явно перед запуском: в Behavior
                    // duration пересчитывался уже после старта анимации, и
                    // затемнение уходило не за 200 мс, а за все 10 с
                    fade.stop()
                    fade.duration = Idle.warning ? Idle.warnSec * 1000 : 200
                    fade.easing.type = Idle.warning ? Easing.InQuad : Easing.OutCubic
                    fade.to = Idle.warning ? 0.65 : 0
                    fade.start()
                }
            }
            Timer {
                running: Idle.warning
                interval: 200
                repeat: true
                onTriggered: warnWin.left = Math.max(0, Idle.warnSec - (Date.now() - warnWin.startedAt) / 1000)
            }

            Rectangle {
                id: dim
                anchors.fill: parent
                color: Theme.crust
                // Темнеет за всё время предупреждения, уходит сразу
                opacity: 0
                NumberAnimation { id: fade; target: dim; property: "opacity" }
            }

            Rectangle {
                anchors.centerIn: parent
                width: row.implicitWidth + 36
                height: 52
                radius: height / 2
                color: Theme.popoutBg
                opacity: Idle.warning ? 1 : 0
                scale: Idle.warning ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on scale { Spring {} }

                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰌾"
                        font.family: Theme.font
                        font.pixelSize: 20
                        color: Theme.mauve
                    }
                    GradientText {
                        anchors.verticalCenter: parent.verticalCenter
                        pixelSize: 15
                        text: "Заблокирую через " + Math.ceil(warnWin.left) + " с"
                    }
                }
            }
        }
    }
}
