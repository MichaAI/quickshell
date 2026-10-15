pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import "../../config"
import "../../services"
import "../../components"

Item {
    id: root

    implicitWidth: 380
    implicitHeight: col.implicitHeight + 24

    component Card: Rectangle {
        default property alias content: inner.data
        width: col.width
        implicitHeight: inner.implicitHeight + 20
        radius: 12
        color: Theme.cardBg

        Column {
            id: inner
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
        }
    }

    // Значок + текст поверх неба
    component Chip: Row {
        property alias icon: ic.text
        property alias text: tx.text
        property alias iconRotation: ic.rotation
        spacing: 4
        Text {
            id: ic
            font.family: Theme.font
            font.pixelSize: 13
            color: Theme.subtext1
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            id: tx
            font.family: Theme.font
            font.pixelSize: 12
            color: Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Column {
        id: col
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 12
        width: root.implicitWidth - 24
        spacing: 8

        // ===== Сейчас: живое небо =====
        ClippingRectangle {
            width: parent.width
            height: 136
            radius: 12
            color: Theme.cardBg

            WeatherScene {
                anchors.fill: parent
                kind: Weather.kind
                isDay: Weather.isDay
            }

            Row {
                x: 12; y: 10
                spacing: 5
                Text {
                    text: "󰍎"
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.subtext1
                }
                Text {
                    text: Weather.place
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.subtext1
                }
            }

            Row {
                x: 12; y: 28
                spacing: 12

                Text {
                    text: Math.round(Weather.temp) + "°"
                    font.family: Theme.displayFont
                    font.pixelSize: 54
                    color: Theme.text
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        text: Weather.description
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.text
                    }
                    Text {
                        text: "Ощущается " + Weather.fmt(Weather.feels)
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.subtext1
                    }
                    Text {
                        text: "↑ " + Weather.fmt(Weather.todayMax) + "   ↓ " + Weather.fmt(Weather.todayMin)
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.subtext1
                    }
                }
            }

            Row {
                x: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                spacing: 14

                // Стрелка показывает, куда дует (направление — откуда)
                Chip { icon: "󰁝"; iconRotation: Weather.windDir + 180; text: Math.round(Weather.wind) + " м/с" }
                Chip { icon: "󰖎"; text: Weather.humidity + "%" }
                Chip { icon: "󰖨"; text: "УФ " + Weather.uv.toFixed(0) }
                Chip { icon: "󰖜"; text: Weather.sunrise }
                Chip { icon: "󰖛"; text: Weather.sunset }
            }
        }

        // ===== По часам: кривая температуры =====
        Card {
            Flickable {
                id: hours
                width: parent.width
                height: 92
                contentWidth: hourRow.width
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                readonly property int cell: 46
                readonly property real lo: Math.min(...Weather.hourly.map(h => h.temp))
                readonly property real hi: Math.max(...Weather.hourly.map(h => h.temp))
                // Полоса кривой: от curveTop до curveTop + curveH
                readonly property real curveTop: 50
                readonly property real curveH: 18
                function yOf(t) {
                    const span = Math.max(1, hi - lo)
                    return curveTop + (1 - (t - lo) / span) * curveH
                }

                // Вертикальное колесо листает вбок
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse
                    onWheel: event => {
                        hours.contentX = Math.max(0, Math.min(hours.contentWidth - hours.width,
                            hours.contentX - event.angleDelta.y))
                    }
                }

                Canvas {
                    id: curve
                    width: hourRow.width
                    height: hours.height
                    onWidthChanged: requestPaint()
                    Connections {
                        target: Weather
                        function onHourlyChanged() { curve.requestPaint() }
                    }
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        const pts = Weather.hourly.map((h, i) => [i * hours.cell + hours.cell / 2, hours.yOf(h.temp)])
                        if (pts.length < 2)
                            return
                        const grad = ctx.createLinearGradient(0, 0, width, 0)
                        grad.addColorStop(0, Theme.gradStart)
                        grad.addColorStop(1, Theme.gradEnd)
                        ctx.strokeStyle = grad
                        ctx.lineWidth = 2
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.moveTo(pts[0][0], pts[0][1])
                        // Сглаживание: кривые Безье через середины отрезков
                        for (let i = 1; i < pts.length - 1; i++) {
                            const mx = (pts[i][0] + pts[i + 1][0]) / 2
                            const my = (pts[i][1] + pts[i + 1][1]) / 2
                            ctx.quadraticCurveTo(pts[i][0], pts[i][1], mx, my)
                        }
                        const last = pts[pts.length - 1]
                        ctx.lineTo(last[0], last[1])
                        ctx.stroke()
                    }
                }

                Row {
                    id: hourRow
                    Repeater {
                        model: Weather.hourly
                        delegate: Item {
                            id: hour
                            required property var modelData
                            required property int index
                            width: hours.cell
                            height: hours.height

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0
                                text: hour.modelData.time
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: hour.index === 0 ? Theme.text : Theme.overlay1
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 15
                                text: Weather.iconOf(hour.modelData.code, hour.modelData.isDay)
                                font.family: Theme.font
                                font.pixelSize: 17
                                color: Weather.colorOf(hour.modelData.code, hour.modelData.isDay)
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: hours.yOf(hour.modelData.temp) - 17
                                text: Math.round(hour.modelData.temp) + "°"
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: Theme.text
                            }
                            Rectangle {
                                x: parent.width / 2 - 3
                                y: hours.yOf(hour.modelData.temp) - 3
                                width: 6; height: 6; radius: 3
                                color: Theme.cardBg
                                border.width: 2
                                border.color: Theme.mix(Theme.gradStart, Theme.gradEnd, hour.index / Math.max(1, Weather.hourly.length - 1))
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                text: Weather.rainText(hour.modelData.pop, hour.modelData.mm)
                                font.family: Theme.font
                                font.pixelSize: 10
                                color: Theme.sapphire
                            }
                        }
                    }
                }
            }
        }

        // ===== Неделя: полоски диапазона =====
        Card {
            id: week
            readonly property real lo: Math.min(...Weather.daily.map(d => d.min))
            readonly property real hi: Math.max(...Weather.daily.map(d => d.max))
            function pos(t) { return Math.max(0, Math.min(1, (t - lo) / Math.max(1, hi - lo))) }

            Repeater {
                model: Weather.daily
                delegate: Item {
                    id: day
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 22

                    Text {
                        id: dayName
                        width: 66
                        anchors.verticalCenter: parent.verticalCenter
                        text: day.modelData.name
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: day.index === 0 ? Theme.text : Theme.subtext0
                    }
                    Text {
                        id: dayIcon
                        x: dayName.width
                        width: 24
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.iconOf(day.modelData.code, true)
                        font.family: Theme.font
                        font.pixelSize: 15
                        color: Weather.colorOf(day.modelData.code, true)
                    }
                    Text {
                        id: dayPop
                        x: dayIcon.x + dayIcon.width
                        width: 36
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.rainText(day.modelData.pop, day.modelData.mm)
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.sapphire
                    }
                    Text {
                        id: dayMin
                        x: dayPop.x + dayPop.width
                        width: 32
                        horizontalAlignment: Text.AlignRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(day.modelData.min) + "°"
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.overlay1
                    }
                    Item {
                        id: track
                        x: dayMin.x + dayMin.width + 10
                        width: parent.width - x - 10 - dayMax.width
                        height: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: Theme.surface0
                        }
                        // Цвет полоски — от холодного к тёплому по неделе
                        Rectangle {
                            x: track.width * week.pos(day.modelData.min)
                            width: Math.max(6, track.width * (week.pos(day.modelData.max) - week.pos(day.modelData.min)))
                            height: parent.height
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Theme.mix(Theme.sky, Theme.peach, week.pos(day.modelData.min)) }
                                GradientStop { position: 1; color: Theme.mix(Theme.sky, Theme.peach, week.pos(day.modelData.max)) }
                            }
                        }
                        // Сегодня — где мы сейчас
                        Rectangle {
                            visible: day.index === 0
                            x: track.width * week.pos(Weather.temp) - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10; height: 10; radius: 5
                            color: Theme.text
                            border.width: 2
                            border.color: Theme.cardBg
                        }
                    }
                    Text {
                        id: dayMax
                        anchors.right: parent.right
                        width: 32
                        horizontalAlignment: Text.AlignRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(day.modelData.max) + "°"
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.text
                    }
                }
            }
        }
    }
}
