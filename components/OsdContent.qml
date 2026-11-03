import QtQuick
import "../config"
import "../services"

// Содержимое OSD: иконка, полоса, проценты. Значения — из Osd
Item {
    id: root

    implicitWidth: 300
    implicitHeight: 44

    Text {
        id: ico
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        horizontalAlignment: Text.AlignHCenter
        text: Osd.icon
        font.family: Theme.font
        font.pixelSize: 18
        color: Osd.muted ? Theme.overlay0 : Osd.color
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    ProgressBar {
        anchors.left: ico.right
        anchors.leftMargin: 12
        anchors.right: pct.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        value: Osd.value
        from: Osd.muted ? Theme.overlay0 : Theme.gradStart
        to: Osd.muted ? Theme.overlay0 : Theme.gradEnd
    }

    Text {
        id: pct
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        horizontalAlignment: Text.AlignRight
        text: Osd.muted ? "выкл" : Math.round(Osd.value * 100)
        font.family: Theme.font
        font.pixelSize: 13
        font.features: { "tnum": 1 }
        color: Osd.muted ? Theme.overlay0 : Theme.text
    }
}
