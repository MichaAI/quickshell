pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"
import "../components"

// Всплывающие уведомления: правый верхний угол монитора с фокусом.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow { // qmllint disable uncreatable-type
            id: toastWin
            required property var modelData
            screen: modelData

            readonly property string focusedOutput: Compositor.focusedOutput
            readonly property bool isTarget: focusedOutput !== ""
                ? modelData.name === focusedOutput
                : modelData === Quickshell.screens[0]

            visible: isTarget && Notifs.popups.length > 0
            // Окно фиксированного размера во всю высоту: ресайз layer-surface
            // на каждом кадре анимации дёргал всплывашки. Ввод — только по стопке.
            anchors { top: true; right: true; bottom: true }
            margins { top: 8; right: 8; bottom: 8 } // qmllint disable missing-property
            // Слева запас: всплывашка влетает на пружине и на перелёте
            // проскакивает левее своего места — без запаса её обрезало бы
            implicitWidth: 380 + 32
            mask: Region { item: stack }
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "quickshell:notifications"
            WlrLayershell.layer: WlrLayer.Overlay

            Column {
                id: stack
                anchors.right: parent.right
                width: 380

                Repeater {
                    model: ScriptModel { values: Notifs.popups }

                    NotifItem {
                        id: toast
                        required property var modelData
                        required property int index

                        width: stack.width
                        gap: 8
                        notif: modelData
                        collapse: index < Notifs.popups.length - 1
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
                            function onHidePopupsRequested() {
                                toast.leave(() => Notifs.popupExpired(toast.modelData))
                            }
                        }
                    }
                }
            }
        }
    }
}
