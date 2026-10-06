import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."
import "../services"
import "../components"

// Виджет на рабочем столе: день недели и дата (как eww-окно "test").
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors { right: true; bottom: true }
            margins { right: 48; bottom: 72 }
            implicitWidth: content.implicitWidth + 32
            implicitHeight: content.implicitHeight + 32
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:desktop"
            WlrLayershell.layer: WlrLayer.Bottom

            mask: Region {}

            Column {
                id: content
                anchors.centerIn: parent
                spacing: 14

                GradientText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    pixelSize: 128
                    fontFamily: "Neofolia"
                    fontWeight: Font.Normal
                    italic: false
                    outlineWidth: 6
                    outlineColor: Theme.crust
                    text: {
                        const d = Time.dayOfWeek
                        return d.charAt(0).toUpperCase() + d.slice(1)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Time.dateLong + "  ·  " + Time.time
                    
                    font.family: Theme.font
                    font.pixelSize: 14
                    color: Theme.alpha(Theme.text, 0.75)

                    style: Text.Outline
                    styleColor: Theme.crust
                }
            }
        }
    }
}
