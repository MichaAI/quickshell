import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../../components"

// Меню трея, отрисованное в стиле шелла (с подменю).
Item {
    id: root

    implicitWidth: 300
    implicitHeight: Math.min(col.implicitHeight + 28, Settings.popoutMaxHeight)

    property var stack: []
    readonly property var current: stack.length > 0 ? stack[stack.length - 1] : Ui.trayMenuHandle

    Connections {
        target: Ui
        function onTrayMenuHandleChanged() { root.stack = [] }
    }

    // Корневой хендл держим открытым всё время жизни попаута.
    // QsMenuOpener.setMenu сперва отпускает старое меню и только потом берёт
    // новое; когда единственный opener переключался с корня на подменю,
    // рефкаунт DBusMenuHandle падал до нуля и quickshell сносил всё дерево
    // пунктов — подменю успевало мигнуть и пропадало.
    QsMenuOpener {
        menu: Ui.trayMenuHandle
    }

    QsMenuOpener {
        id: opener
        menu: root.current ?? null
    }

    // Длинные меню (VPN, плееры) не влезают в popoutMaxHeight — даём скролл
    Overscroll {
        flick: flick
        z: 1
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        clip: true
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: col
            width: flick.width
            spacing: 2

            // Назад (для подменю)
            Rectangle {
                visible: root.stack.length > 0
                width: parent.width
                height: 34
                radius: 8
                color: backMa.containsMouse ? Theme.cardBg : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    spacing: 8

                    Text {
                        text: "󰅁"
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.mauve
                    }
                    GradientText {
                        pixelSize: 12
                        text: "Назад"
                    }
                }

                MouseArea {
                    id: backMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.stack = root.stack.slice(0, -1)
                }
            }

            Repeater {
                model: opener.children

                Rectangle {
                    id: entry
                    required property var modelData

                    width: col.width
                    height: modelData.isSeparator ? 11 : 34
                    radius: 8
                    color: !modelData.isSeparator && modelData.enabled && ema.containsMouse
                        ? Theme.cardBg : "transparent"

                    // Разделитель
                    Rectangle {
                        visible: entry.modelData.isSeparator
                        anchors.centerIn: parent
                        width: parent.width - 16
                        height: 1
                        color: Theme.surface0
                    }

                    Row {
                        id: erow
                        visible: !entry.modelData.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: entry.modelData.hasChildren ? 28 : 8
                        spacing: 8

                        Text {
                            id: mark
                            visible: entry.modelData.buttonType !== QsMenuButtonType.None
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 13
                            color: entry.modelData.checkState === Qt.Checked ? Theme.green : Theme.overlay0
                            text: entry.modelData.buttonType === QsMenuButtonType.RadioButton
                                ? (entry.modelData.checkState === Qt.Checked ? "󰐾" : "󰄰")
                                : (entry.modelData.checkState === Qt.Checked ? "󰄲" : "󰄱")
                        }

                        Image {
                            id: icon
                            visible: source.toString() !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            source: entry.modelData.icon ?? ""
                            width: 16
                            height: 16
                            sourceSize.width: 16
                            sourceSize.height: 16
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: erow.width
                                 - (mark.visible ? mark.width + erow.spacing : 0)
                                 - (icon.visible ? icon.width + erow.spacing : 0)
                            text: entry.modelData.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: entry.modelData.enabled ? Theme.text : Theme.overlay0
                        }
                    }

                    Text {
                        visible: !entry.modelData.isSeparator && entry.modelData.hasChildren
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰅂"
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.overlay0
                    }

                    MouseArea {
                        id: ema
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !entry.modelData.isSeparator && entry.modelData.enabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (entry.modelData.hasChildren) {
                                root.stack = [...root.stack, entry.modelData]
                            } else {
                                entry.modelData.triggered()
                                Ui.closePopouts()
                            }
                        }
                    }
                }
            }

            // Пустое меню
            Text {
                visible: (opener.children?.values.length ?? 0) === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: 6
                bottomPadding: 6
                text: "Меню пустое"
                font.family: Theme.font
                font.pixelSize: 12
                font.italic: true
                color: Theme.overlay0
            }
        }
    }
}
