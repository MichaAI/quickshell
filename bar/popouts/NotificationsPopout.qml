pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import "../../config"
import "../../services"
import "../../components"

// Центр уведомлений: история, «Не беспокоить», очистка.
Item {
    id: root

    implicitWidth: 380
    implicitHeight: Math.min(header.height + 14 + 10 + body.contentH + 16, Settings.popoutMaxHeight)

    // Открыли центр — всё прочитано
    Component.onCompleted: Notifs.unread = false

    component HeadBtn: Rectangle {
        property alias label: t.text
        property bool on: false
        property color onColor: Theme.mauve
        signal pressed()
        width: 28; height: 28; radius: 8
        color: hma.containsMouse ? Theme.cardBg : "transparent"
        Text {
            id: t
            anchors.centerIn: parent
            font.family: Theme.font
            font.pixelSize: 15
            color: parent.on ? parent.onColor
                 : hma.containsMouse ? Theme.text : Theme.overlay1
        }
        MouseArea {
            id: hma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.pressed()
        }
    }

    // Шапка: Уведомления (N)            [DND] [очистить]
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 14
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        height: 30

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            GradientText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Уведомления"
                pixelSize: 15
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Notifs.count > 0
                text: Notifs.count
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.overlay1
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            HeadBtn {
                label: Notifs.dnd ? "󰂛" : "󰂚"
                on: Notifs.dnd
                onColor: Theme.red
                onPressed: Notifs.toggleDnd()
            }
            HeadBtn {
                label: "󰎟"
                visible: Notifs.count > 0
                onPressed: Notifs.clearAll()
            }
        }
    }

    Rectangle {
        id: sep
        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        height: 1
        gradient: OkGradient {
            orientation: Gradient.Horizontal
            from: Theme.alpha(Theme.gradStart, 0.4)
            to: Theme.alpha(Theme.gradEnd, 0.4)
        }
    }

    Item {
        id: body

        readonly property real contentH: Notifs.count > 0
            ? list.contentHeight + 10
            : empty.implicitHeight + 30

        anchors.top: sep.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 14

        // Пусто
        Column {
            id: empty
            visible: Notifs.count === 0
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifs.dnd ? "󰂛" : "󰂜"
                font.family: Theme.font
                font.pixelSize: 32
                color: Theme.surface2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifs.dnd ? "Не беспокоить" : "Тишина и покой"
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.overlay1
            }
        }

        // Растяжка у краёв — поверх списка
        Overscroll {
            flick: list
            z: 1
        }

        ListView {
            id: list
            anchors.fill: parent
            anchors.topMargin: 10
            visible: Notifs.count > 0
            clip: true
            spacing: 0
            model: ScriptModel { values: Notifs.list }
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            delegate: NotifItem {
                id: item
                required property var modelData
                required property int index
                width: list.width
                gap: 6
                notif: modelData
                collapse: index < list.count - 1

                function leaveForClear() {
                    const d = Notifs.clearDelay(item.index)
                    Notifs.holdClear(d)
                    item.leave(null, d)
                }

                // Делегаты ленивые: подъехавшая снизу посреди очистки карточка
                // не слышала clearRequested — встаёт в волну на своё место
                Component.onCompleted: if (Notifs.clearing) leaveForClear()

                Connections {
                    target: Notifs
                    function onClearRequested() { item.leaveForClear() }
                }
            }
        }
    }
}
