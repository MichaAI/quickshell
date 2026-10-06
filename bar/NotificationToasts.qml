pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."
import "../services"
import "../components"

// Всплывающие уведомления: правый верхний угол монитора с фокусом.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: toastWin
            required property var modelData
            screen: modelData

            readonly property string focusedOutput: Niri.focusedWorkspace?.output ?? ""
            readonly property bool isTarget: focusedOutput !== ""
                ? modelData.name === focusedOutput
                : modelData === Quickshell.screens[0]

            visible: isTarget && Notifs.popups.length > 0
            anchors { top: true; right: true }
            margins { top: 8; right: 8 }
            implicitWidth: 380
            implicitHeight: Math.max(1, stack.implicitHeight)
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "quickshell:notifications"
            WlrLayershell.layer: WlrLayer.Overlay

            Column {
                id: stack
                width: parent.width
                spacing: 8

                move: Transition {
                    NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic }
                }

                Repeater {
                    model: ScriptModel { values: Notifs.popups }

                    Item {
                        id: toast
                        required property var modelData

                        width: stack.width
                        height: card.implicitHeight + 8

                        // Въезд справа
                        property real slide: 1
                        Component.onCompleted: slide = 0
                        Behavior on slide {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }

                        Timer {
                            interval: Notifs.popupTimeout
                            // Критичные висят до клика
                            running: !card.hovered && !card.critical
                            onTriggered: Notifs.popupExpired(toast.modelData)
                        }

                        // Подложка в цвет бара — как у попаутов
                        Rectangle {
                            width: parent.width
                            height: parent.height
                            x: toast.slide * (toast.width + 16)
                            radius: Settings.popoutRadius
                            color: Theme.popoutBg
                            opacity: 1 - toast.slide

                            NotifCard {
                                id: card
                                anchors.fill: parent
                                anchors.margins: 4
                                notif: toast.modelData
                                onClosePressed: {
                                    Notifs.dropPopup(toast.modelData)
                                    toast.modelData.dismiss()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
