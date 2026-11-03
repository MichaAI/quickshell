import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"
import "../components"

// Виджет на рабочем столе: день недели и дата (как eww-окно "test").
// Под niri — в углу каждого монитора. Под driftwm его кладёт на холст
// правило с position на app_id "quickshell:desktop" в конфиге driftwm, а
// правила разбираются по одному на поверхность — поэтому копия одна
Scope {
    Variants {
        model: Compositor.name !== "driftwm" ? Quickshell.screens
            : Quickshell.screens.length > 0 ? [Quickshell.screens[0]] : []

        PanelWindow { // qmllint disable uncreatable-type
            required property var modelData
            screen: modelData

            anchors { right: true; bottom: true }
            margins { right: 48; bottom: 72 } // qmllint disable missing-property
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
                    display: true
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
