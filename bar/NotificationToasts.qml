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

                Repeater {
                    model: ScriptModel { values: Notifs.popups }

                    NotifItem {
                        id: toast
                        required property var modelData

                        width: stack.width
                        gap: 8
                        notif: modelData
                        enter: true
                        slide: 1

                        Timer {
                            interval: Notifs.popupTimeout
                            // Критичные висят до клика
                            running: !toast.hovered && !toast.critical && !toast.leaving
                            onTriggered: toast.leave(() => Notifs.popupExpired(toast.modelData))
                        }

                        Connections {
                            target: Notifs
                            function onClearRequested() { toast.leave(null) }
                        }
                    }
                }
            }
        }
    }
}
