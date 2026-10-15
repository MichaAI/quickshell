import QtQuick
import "../../config"
import "../../services"
import "../../components"

Item {
    id: root

    implicitWidth: 300
    implicitHeight: col.implicitHeight + 28

    property int year: new Date().getFullYear()
    property int month: new Date().getMonth()

    readonly property var days: {
        const first = new Date(year, month, 1)
        const offset = (first.getDay() + 6) % 7
        const dim = new Date(year, month + 1, 0).getDate()
        const dimPrev = new Date(year, month, 0).getDate()
        const arr = []
        for (let i = 0; i < 42; i++) {
            const d = i - offset + 1
            if (d < 1) arr.push({ day: dimPrev + d, cur: false })
            else if (d > dim) arr.push({ day: d - dim, cur: false })
            else arr.push({ day: d, cur: true })
        }
        return arr
    }

    function shift(d) {
        let m = month + d
        if (m < 0) { m = 11; year-- }
        else if (m > 11) { m = 0; year++ }
        month = m
    }

    function reset() {
        year = new Date().getFullYear()
        month = new Date().getMonth()
    }

    component NavBtn: Rectangle {
        property alias label: t.text
        signal pressed()
        width: 28; height: 28; radius: 8
        color: nma.containsMouse ? Theme.cardBg : "transparent"
        Text {
            id: t
            anchors.centerIn: parent
            font.family: Theme.font
            font.pixelSize: 15
            color: Theme.mauve
        }
        MouseArea {
            id: nma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.pressed()
        }
    }

    Column {
        id: col
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 14
        spacing: 10

        // Шапка: ‹ Месяц Год ›
        Item {
            width: grid.width
            height: 30

            NavBtn {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                label: "󰅁"
                onPressed: root.shift(-1)
            }

            GradientText {
                id: monthText
                anchors.centerIn: parent
                pixelSize: 15
                text: {
                    const n = Qt.locale().standaloneMonthName(root.month, Locale.LongFormat)
                    return n.charAt(0).toUpperCase() + n.slice(1) + " " + root.year
                }
            }

            MouseArea {
                anchors.fill: monthText
                cursorShape: Qt.PointingHandCursor
                onClicked: root.reset()
            }

            NavBtn {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "󰅂"
                onPressed: root.shift(1)
            }
        }

        // Дни недели
        Row {
            spacing: 4
            Repeater {
                model: 7
                Item {
                    required property int index
                    width: 32; height: 20
                    Text {
                        anchors.centerIn: parent
                        text: Qt.locale().dayName((index + 1) % 7, Locale.ShortFormat)
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: index >= 5 ? Theme.red : Theme.overlay1
                    }
                }
            }
        }

        // Сетка дней
        Grid {
            id: grid
            columns: 7
            spacing: 4

            Repeater {
                model: root.days

                Rectangle {
                    id: cell
                    required property var modelData
                    required property int index

                    readonly property bool isToday: {
                        const n = Time.now
                        return modelData.cur
                            && modelData.day === n.getDate()
                            && root.month === n.getMonth()
                            && root.year === n.getFullYear()
                    }

                    width: 32; height: 32
                    radius: 10
                    color: isToday ? "transparent" : (cma.containsMouse ? Theme.cardBg : "transparent")

                    gradient: isToday ? todayGrad : null
                    OkGradient {
                        id: todayGrad
                        orientation: Gradient.Horizontal
                        from: Theme.gradStart
                        to: Theme.gradEnd
                    }

                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData.day
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: cell.isToday ? Font.Bold : Font.Normal
                        color: cell.isToday ? Theme.crust
                             : cell.modelData.cur
                               ? (cell.index % 7 >= 5 ? Theme.red : Theme.text)
                               : Theme.surface2
                    }

                    MouseArea {
                        id: cma
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
            }
        }

        // Сегодняшняя дата
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Time.dateLong
            font.family: Theme.font
            font.pixelSize: 11
            color: Theme.overlay1
        }
    }
}
