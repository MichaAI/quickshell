import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."
import "../components"

// Нижние внутренние углы монитора: не занимают место и прозрачны для мыши.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: cornersWin
            required property var modelData
            screen: modelData

            anchors { left: true; right: true; bottom: true }
            implicitHeight: Settings.screenRadius
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:corners"
            WlrLayershell.layer: WlrLayer.Top

            mask: Region {}

            InnerCorner {
                x: 0
                y: 0
                flipY: true
            }
            InnerCorner {
                x: cornersWin.width - width
                y: 0
                flipX: true
                flipY: true
            }
        }
    }
}
