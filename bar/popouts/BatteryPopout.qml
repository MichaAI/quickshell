import QtQuick
import "../../config"
import "../../services"
import "../../components"

Item {
    id: root

    implicitWidth: 300
    implicitHeight: col.implicitHeight + 28

    component KV: Item {
        property alias key: k.text
        property alias value: v.text
        width: parent.width
        height: 20

        Text {
            id: k
            anchors.left: parent.left
            font.family: Theme.font
            font.pixelSize: 12
            color: Theme.overlay1
        }
        Text {
            id: v
            anchors.right: parent.right
            font.family: Theme.font
            font.pixelSize: 12
            color: Theme.text
        }
    }

    Column {
        id: col
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 16
        width: root.implicitWidth - 32
        spacing: 10

        // Заряд — волнистое кольцо; волна бежит, пока заряжается
        WavyRing {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 132
            height: 132
            value: Power.percent / 100
            moving: Power.charging
            from: Power.critical ? Theme.red : Theme.gradStart
            to: Power.critical ? Theme.maroon : Theme.gradEnd

            Column {
                anchors.centerIn: parent

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Power.icon
                    font.family: Theme.font
                    font.pixelSize: 16
                    color: Power.critical ? Theme.red
                         : Power.charging ? Theme.green : Theme.overlay1
                }
                MorphText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font: "neofolia"
                    pixelSize: 36
                    color: Power.critical ? Theme.red : Theme.gradStart
                    colorTo: Power.critical ? Theme.maroon : Theme.gradEnd
                    text: Power.percent + "%"
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Power.stateText
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.subtext1
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Power.timeText
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.overlay1
                visible: text !== "" && text !== "—"
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            gradient: OkGradient {
                orientation: Gradient.Horizontal
                from: Theme.alpha(Theme.gradStart, 0.4)
                to: Theme.alpha(Theme.gradEnd, 0.4)
            }
        }

        KV {
            key: "Мощность"
            value: Power.device ? Math.abs(Power.device.changeRate).toFixed(1) + " Вт" : "—"
        }
        KV {
            visible: Power.device?.healthSupported ?? false
            key: "Здоровье"
            value: Power.device ? Math.round(Power.device.healthPercentage) + "%" : "—"
        }
        KV {
            key: "Заряд"
            value: Power.device
                ? Power.device.energy.toFixed(1) + " / " + Power.device.energyCapacity.toFixed(1) + " Вт·ч"
                : "—"
        }
    }
}
