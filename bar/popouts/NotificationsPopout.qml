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

    // ===== Стопки по приложениям (Settings.notifGroups) =====
    // Порядок стопок — по самому свежему уведомлению в них
    readonly property var groups: {
        const seen = [], out = []
        for (const n of Notifs.list) {
            const key = n.appName || "Уведомление"
            if (!seen.includes(key)) {
                seen.push(key)
                out.push({ key: key })
            }
        }
        return out
    }
    function groupItems(key) {
        return Notifs.list.filter(n => (n.appName || "Уведомление") === key)
    }
    // Раскрытые стопки — по имени приложения, переживают обновление списка
    property var expanded: ({})
    function toggleGroup(key) {
        const e = Object.assign({}, expanded)
        e[key] = !e[key]
        expanded = e
    }

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
            model: Settings.notifGroups ? groupModel : itemModel
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            ScriptModel { id: itemModel; values: Notifs.list }
            // Стопка опознаётся по приложению: делегат и его раскрытие живут,
            // пока в стопке что-то есть
            ScriptModel { id: groupModel; values: root.groups; objectProp: "key" }

            delegate: Settings.notifGroups ? groupDelegate : itemDelegate

            Component {
                id: itemDelegate
                NotifItem {
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

            Component {
                id: groupDelegate

                Item {
                    id: group
                    required property var modelData
                    required property int index
                    readonly property string key: modelData.key
                    readonly property var items: root.groupItems(key)
                    readonly property bool many: items.length > 1
                    readonly property bool open: many && root.expanded[key] === true
                    readonly property var shownItems: open ? items : items.slice(0, 1)

                    width: list.width
                    // Высота пружинит, когда стопка раскрывается
                    height: column.implicitHeight
                    Behavior on height { Spring { epsilon: 0.5 } }
                    clip: true

                    Column {
                        id: column
                        width: parent.width

                        // Шапка стопки: приложение, сколько, раскрыть
                        Item {
                            visible: group.many
                            width: parent.width
                            height: visible ? 24 : 0

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Text {
                                    text: group.key
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Theme.subtext1
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: countText.implicitWidth + 10
                                    height: 16
                                    radius: 8
                                    color: Theme.surface0
                                    Text {
                                        id: countText
                                        anchors.centerIn: parent
                                        text: group.items.length
                                        font.family: Theme.font
                                        font.pixelSize: 10
                                        color: Theme.subtext0
                                    }
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰅀"
                                font.family: Theme.font
                                font.pixelSize: 14
                                color: headHover.hovered ? Theme.text : Theme.overlay1
                                rotation: group.open ? 180 : 0
                                Behavior on rotation { Spring {} }
                            }
                            HoverHandler {
                                id: headHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                onTapped: root.toggleGroup(group.key)
                            }
                        }

                        Repeater {
                            model: ScriptModel { values: group.shownItems }

                            NotifItem {
                                id: gItem
                                required property var modelData
                                required property int index
                                width: group.width
                                gap: 6
                                notif: modelData
                                // Раскрытые выезжают справа, как новые
                                enter: gItem.index > 0
                                collapse: group.index < list.count - 1 || gItem.index < group.shownItems.length - 1

                                function leaveForClear() {
                                    const d = Notifs.clearDelay(group.index + gItem.index)
                                    Notifs.holdClear(d)
                                    gItem.leave(null, d)
                                }
                                Component.onCompleted: if (Notifs.clearing) leaveForClear()
                                Connections {
                                    target: Notifs
                                    function onClearRequested() { gItem.leaveForClear() }
                                }
                            }
                        }

                        // Свёрнутая стопка: из-под карточки выглядывают ещё две
                        Item {
                            visible: group.many && !group.open
                            width: parent.width
                            height: visible ? 8 : 0
                            Rectangle {
                                x: 10; y: -6
                                width: parent.width - 20; height: 8
                                radius: 6
                                color: Theme.surface0
                            }
                            Rectangle {
                                x: 20; y: -2
                                width: parent.width - 40; height: 8
                                radius: 6
                                visible: group.items.length > 2
                                color: Theme.alpha(Theme.surface0, 0.5)
                            }
                        }
                    }
                }
            }
        }
    }
}
