import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import ".."
import "../services"

// Карточка уведомления — общая для центра и всплывашек.
Rectangle {
    id: root

    required property Notification notif
    property color baseColor: Theme.crust
    readonly property bool hovered: hover.hovered
    readonly property bool critical: notif?.urgency === NotificationUrgency.Critical

    signal closePressed()

    implicitHeight: content.implicitHeight + 24
    radius: 12
    color: cma.containsMouse ? Theme.mix(baseColor, Theme.base, 0.6) : baseColor
    border.width: 2
    border.color: Theme.base
    Behavior on color { ColorAnimation { duration: 120 } }

    HoverHandler { id: hover }

    // Клик по карточке — действие по умолчанию
    MouseArea {
        id: cma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Notifs.activate(root.notif)
    }

    // Критичные помечаем полоской слева
    Rectangle {
        visible: root.critical
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 24
        radius: 2
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.red }
            GradientStop { position: 1; color: Theme.maroon }
        }
    }

    Row {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        spacing: 12

        // Картинка уведомления > иконка приложения > колокольчик
        ClippingRectangle {
            id: pic
            width: 38; height: 38
            radius: 10
            color: Theme.surface0

            readonly property string src: {
                const n = root.notif
                if (!n) return ""
                if (n.image !== "") return n.image
                const i = n.appIcon
                if (i === "") return ""
                if (i.startsWith("/") || i.includes("://")) return i
                return Quickshell.iconPath(i, true)
            }

            Image {
                id: picImg
                anchors.fill: parent
                source: pic.src
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 76
                sourceSize.height: 76
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: !picImg.visible
                text: "󰂚"
                font.family: Theme.font
                font.pixelSize: 18
                color: root.critical ? Theme.red : Theme.mauve
            }
        }

        Column {
            width: parent.width - pic.width - parent.spacing
            spacing: 3

            // Приложение · время            ✕
            Item {
                width: parent.width
                height: 16

                Text {
                    anchors.left: parent.left
                    anchors.right: closeBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const app = root.notif?.appName || "Уведомление"
                        const t = root.notif ? Notifs.ago(root.notif) : ""
                        return t !== "" ? app + "  ·  " + t : app
                    }
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.overlay1
                }

                Text {
                    id: closeBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅖"
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: xma.containsMouse ? Theme.red : Theme.overlay0
                    opacity: root.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    MouseArea {
                        id: xma
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closePressed()
                    }
                }
            }

            Text {
                width: parent.width
                text: root.notif?.summary ?? ""
                visible: text !== ""
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.critical ? Theme.red : Theme.text
            }

            Text {
                width: parent.width
                text: root.notif ? Notifs.bodyText(root.notif) : ""
                visible: text !== ""
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                textFormat: Text.StyledText
                linkColor: Theme.sapphire
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.subtext0
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // Кнопки действий (кроме default — он на клике по карточке)
            Flow {
                id: actions
                readonly property var list: (root.notif?.actions ?? [])
                    .filter(a => a.identifier !== "default" && a.text !== "")
                visible: list.length > 0
                width: parent.width
                topPadding: 4
                spacing: 6

                Repeater {
                    model: actions.list

                    Rectangle {
                        id: chip
                        required property var modelData
                        width: at.implicitWidth + 20
                        height: 24
                        radius: 12
                        color: ama.containsMouse ? Theme.surface1 : Theme.surface0

                        Text {
                            id: at
                            anchors.centerIn: parent
                            text: chip.modelData.text
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: ama.containsMouse ? Theme.mauve : Theme.subtext1
                        }
                        MouseArea {
                            id: ama
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: chip.modelData.invoke()
                        }
                    }
                }
            }
        }
    }
}
