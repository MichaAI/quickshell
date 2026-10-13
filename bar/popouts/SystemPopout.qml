import QtQuick
import "../.."
import "../../services"
import "../../components"

Item {
    id: root

    implicitWidth: 380
    implicitHeight: col.implicitHeight + 28

    component Card: Rectangle {
        default property alias content: inner.data
        width: col.width
        implicitHeight: inner.implicitHeight + 24
        radius: 12
        color: Theme.cardBg

        Column {
            id: inner
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
        }
    }

    component CardTitle: Item {
        property alias icon: i.text
        property alias iconColor: i.color
        property alias title: t.text
        default property alias extra: extraRow.data
        width: parent.width
        height: 20

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                id: i
                font.family: Theme.font
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }
            GradientText {
                id: t
                pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            id: extraRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
        }
    }

    component Meter: Item {
        property real value: 0
        width: parent.width
        height: 8

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Theme.surface0
        }
        Rectangle {
            width: Math.max(8, parent.width * Math.min(1, parent.value))
            height: parent.height
            radius: 4
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.gradStart }
                GradientStop { position: 1; color: Theme.gradEnd }
            }
            Behavior on width { Spring {} }
        }
    }

    component KV: Item {
        property alias key: k.text
        property alias value: v.text
        property alias valueColor: v.color
        width: parent.width
        height: 18

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

    function norm(hist) {
        const m = Math.max(...hist, 100 * 1024)
        return hist.map(v => v / m)
    }

    Column {
        id: col
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 14
        width: root.implicitWidth - 28
        spacing: 10

        // ===== Процессор =====
        Card {
            CardTitle {
                icon: "󰻠"; iconColor: Theme.green; title: "Процессор"

                Text {
                    text: "󰔏 " + SysStat.temp.toFixed(0) + "°C"
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: SysStat.temp > 80 ? Theme.red : Theme.peach
                }
                Text {
                    text: SysStat.cpu.toFixed(0) + "%"
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: Theme.text
                }
            }
            Sparkline {
                width: parent.width
                height: 36
                values: SysStat.cpuHist
                color: Theme.green
            }
        }

        // ===== Память =====
        Card {
            CardTitle {
                icon: "󰍛"; iconColor: Theme.blue; title: "Память"
                Text {
                    text: SysStat.memUsed.toFixed(1) + " / " + SysStat.memTotal.toFixed(1) + " GiB"
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.text
                }
            }
            Meter { value: SysStat.memPerc / 100 }

            KV {
                visible: SysStat.swapTotal > 0
                key: "Swap"
                value: SysStat.swapUsed.toFixed(1) + " / " + SysStat.swapTotal.toFixed(1) + " GiB"
            }
        }

        // ===== Диск =====
        Card {
            CardTitle {
                icon: "󰋊"; iconColor: Theme.yellow; title: "Диск /"
                Text {
                    text: SysStat.diskUsed.toFixed(0) + " / " + SysStat.diskTotal.toFixed(0) + " GiB"
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.text
                }
            }
            Meter { value: SysStat.diskPerc / 100 }

            KV { key: "󰇚 Чтение"; value: SysStat.fmtBytes(SysStat.ioRead) + "/s"; valueColor: Theme.sky }
            KV { key: "󰕒 Запись"; value: SysStat.fmtBytes(SysStat.ioWrite) + "/s"; valueColor: Theme.maroon }
        }

        // ===== Сеть =====
        Card {
            CardTitle {
                icon: "󰛳"; iconColor: Theme.sapphire; title: "Сеть"
                Text {
                    text: "󰇚 " + SysStat.fmtBytes(SysStat.netRx) + "/s   󰕒 " + SysStat.fmtBytes(SysStat.netTx) + "/s"
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.text
                }
            }
            Row {
                width: parent.width
                spacing: 8
                Sparkline {
                    width: (parent.width - 8) / 2
                    height: 30
                    values: root.norm(SysStat.netRxHist)
                    color: Theme.sapphire
                }
                Sparkline {
                    width: (parent.width - 8) / 2
                    height: 30
                    values: root.norm(SysStat.netTxHist)
                    color: Theme.mauve
                }
            }
        }
    }
}
