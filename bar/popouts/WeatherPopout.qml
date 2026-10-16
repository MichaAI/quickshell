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

    // Что в главной карточке: сейчас, выбранный день или выбранный час.
    // Час и день связаны в обе стороны: клик по часу выделяет его день в
    // неделе, клик по дню прокручивает ленту часов к нему
    property int sel: 0                 // выбранный день
    property real selHourTs: -1         // выбранный час; -1 — не выбран
    readonly property var selHour: selHourTs < 0 ? null : Weather.allHours.find(h => h.ts === selHourTs) ?? null
    readonly property bool now: !selHour && (sel === 0 || !selDay)
    readonly property var selDay: Weather.daily[sel] ?? null
    // Лента часов — весь прогноз подряд, через полночь
    readonly property var stripHours: Weather.allHours

    // День, в который попадает момент ts
    function dayIndexOf(ts) {
        for (let i = Weather.daily.length - 1; i >= 0; i--)
            if (ts >= Weather.daily[i].ts)
                return i
        return 0
    }

    function select(i) {
        selHourTs = -1
        sel = Math.max(0, Math.min(Weather.daily.length - 1, i))
        hours.scrollToDay(sel)
    }
    function selectHour(i) {
        const h = stripHours[i]
        if (!h)
            return
        // Первый час — это «сейчас»
        selHourTs = i === 0 ? -1 : h.ts
        sel = dayIndexOf(h.ts)
    }

    // Что показывает карточка: значения часа, дня или текущие
    readonly property var shown: selHour ? {
        kind: Weather.kindOf(selHour.code), isDay: selHour.isDay, time: selHour.ts,
        temp: selHour.temp, text: Weather.textOf(selHour.code),
        sub: (Weather.rainText(selHour.pop, selHour.mm) || "без") + " осадков"
    } : now ? {
        kind: Weather.kind, isDay: Weather.isDay, time: clock.now,
        temp: Weather.temp, text: Weather.description, sub: "Ощущается " + Weather.fmt(Weather.feels)
    } : {
        kind: Weather.kindOf(selDay.code), isDay: true, time: selDay.ts + 13 * 3600000,
        temp: selDay.max, text: Weather.textOf(selDay.code),
        sub: (Weather.rainText(selDay.pop, selDay.mm) || "без") + " осадков"
    }
    // Восход и закат дня в карточке; у дальних дней met.no их не даёт — берём сегодняшние
    readonly property string riseOf: (now ? Weather.sunrise : selDay?.rise) || Weather.sunrise
    readonly property string setOf: (now ? Weather.sunset : selDay?.set) || Weather.sunset

    // Солнце и луна по живому небу двигаются и без выбора: раз в минуту
    QtObject {
        id: clock
        property real now: Date.now()
    }
    Timer {
        interval: 60000
        running: root.visible
        repeat: true
        onTriggered: clock.now = Date.now()
    }

    component Card: Rectangle {
        default property alias content: inner.data
        property alias spacing: inner.spacing
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

        // ===== Сейчас или выбранный день: живое небо =====
        ClippingRectangle {
            width: parent.width
            height: 136
            radius: 12
            color: Theme.cardBg
            // Появляется и пружинит целиком (PopoutReveal): по частям небо
            // съезжало внутри рамки, а текст и ореолы солнца — отдельно от него
            readonly property bool revealWhole: true

            WeatherScene {
                anchors.fill: parent
                kind: root.shown.kind
                isDay: root.shown.isDay
                time: root.shown.time
                rise: root.riseOf
                set: root.setOf
                // Ветер есть только у «сейчас»: у дней в прогнозе его нет
                wind: root.now ? Weather.wind : 0
                windDir: Weather.windDir
            }

            // Колесо листает дни
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (event.angleDelta.y !== 0)
                        root.select(root.sel + (event.angleDelta.y < 0 ? 1 : -1))
                }
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
                    text: root.now ? Weather.place
                        : Weather.place + "  ·  " + Weather.longDate(root.selDay.ts)
                          + (root.selHour ? ", " + new Date(root.selHour.ts).getHours() + ":00" : "")
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.subtext1
                }
            }

            Row {
                x: 12; y: 28
                spacing: 12

                MorphText {
                    text: Math.round(root.shown.temp) + "°"
                    font: "neofolia"
                    pixelSize: 54
                    color: Theme.text
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        text: root.shown.text
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.text
                    }
                    Text {
                        text: root.shown.sub
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.subtext1
                    }
                    Text {
                        text: "↑ " + Weather.fmt(root.now ? Weather.todayMax : root.selDay.max)
                            + "   ↓ " + Weather.fmt(root.now ? Weather.todayMin : root.selDay.min)
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
                // Ветер и влажность — только сейчас: на день источники их не дают
                Chip { visible: root.now; icon: "󰁝"; iconRotation: Weather.windDir + 180; text: Math.round(Weather.wind) + " м/с" }
                Chip { visible: root.now; icon: "󰖎"; text: Weather.humidity + "%" }
                Chip { icon: "󰖨"; text: "УФ " + (root.now ? Weather.uv : root.selDay.uv).toFixed(0) }
                Chip { visible: text !== ""; icon: "󰖜"; text: root.now ? Weather.sunrise : root.selDay.rise }
                Chip { visible: text !== ""; icon: "󰖛"; text: root.now ? Weather.sunset : root.selDay.set }
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
                readonly property real lo: Math.min(...root.stripHours.map(h => h.temp))
                readonly property real hi: Math.max(...root.stripHours.map(h => h.temp))
                // Полоса кривой: от curveTop до curveTop + curveH
                readonly property real curveTop: 50
                readonly property real curveH: 18
                function yOf(t) {
                    const span = Math.max(1, hi - lo)
                    return curveTop + (1 - (t - lo) / span) * curveH
                }

                // К дню i: сегодня — к началу, другой день — к его утру
                function scrollToDay(i) {
                    const day = Weather.daily[i]
                    if (!day)
                        return
                    let idx = 0
                    if (i > 0) {
                        idx = root.stripHours.findIndex(h => h.ts >= day.ts && new Date(h.ts).getHours() >= 6)
                        if (idx < 0)
                            idx = root.stripHours.findIndex(h => h.ts >= day.ts)
                    }
                    scrollAnim.to = Math.max(0, Math.min(Math.max(0, idx) * cell, contentWidth - width))
                    scrollAnim.restart()
                }
                NumberAnimation {
                    id: scrollAnim
                    target: hours; property: "contentX"
                    duration: 450; easing.type: Easing.OutCubic
                }
                // День в начале видимой части ленты — его отмечаем в неделе
                readonly property int viewDay: {
                    const h = root.stripHours[Math.floor((contentX + cell) / cell)]
                    return h ? root.dayIndexOf(h.ts) : 0
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
                        target: root
                        function onStripHoursChanged() { curve.requestPaint() }
                    }
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        const pts = root.stripHours.map((h, i) => [i * hours.cell + hours.cell / 2, hours.yOf(h.temp)])
                        if (pts.length < 2)
                            return
                        const grad = Theme.okStops(ctx.createLinearGradient(0, 0, width, 0), Theme.gradStart, Theme.gradEnd)
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
                        model: root.stripHours
                        delegate: Item {
                            id: hour
                            required property var modelData
                            required property int index
                            readonly property bool picked: root.selHour ? root.selHourTs === hour.modelData.ts : hour.index === 0 && root.now
                            // Полночь — подпись дня вместо «00»
                            readonly property bool midnight: hour.index > 0 && new Date(hour.modelData.ts).getHours() === 0
                            // Часы чужого дня приглушены, когда выбран день или час
                            readonly property bool inFocus: root.now || root.dayIndexOf(hour.modelData.ts) === root.sel
                            width: hours.cell
                            height: hours.height
                            opacity: inFocus ? 1 : 0.45
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: 2
                                anchors.rightMargin: 2
                                radius: 8
                                color: hour.picked ? Theme.surface0
                                     : hourHover.hovered ? Theme.alpha(Theme.surface0, 0.5) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            // Граница суток
                            Rectangle {
                                visible: hour.midnight
                                width: 1
                                height: parent.height - 8
                                y: 4
                                color: Theme.surface1
                            }
                            HoverHandler {
                                id: hourHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                onTapped: root.selectHour(hour.index)
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0
                                text: hour.midnight ? Weather.dayNames[new Date(hour.modelData.ts).getDay()] : hour.modelData.time
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.bold: hour.midnight
                                color: hour.modelData.time === "Сейч" || hour.midnight || hour.picked ? Theme.text : Theme.overlay1
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
                                border.color: Theme.mix(Theme.gradStart, Theme.gradEnd, hour.index / Math.max(1, root.stripHours.length - 1))
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
        // Строки плотно: весь попаут обязан влезть в Settings.popoutMaxHeight,
        // иначе низ обрезается
        Card {
            id: week
            spacing: 2
            readonly property real lo: Math.min(...Weather.daily.map(d => d.min))
            readonly property real hi: Math.max(...Weather.daily.map(d => d.max))
            function pos(t) { return Math.max(0, Math.min(1, (t - lo) / Math.max(1, hi - lo))) }

            // Наведение и клик — один обработчик на весь список, строка — по y.
            // С MouseArea на каждой строке подсветка залипала на прошлой
            readonly property int rowPitch: 22 + spacing
            readonly property int hoverIdx: weekHover.hovered ? rowAt(weekHover.point.position.y) : -1
            function rowAt(y) {
                return Math.max(0, Math.min(Weather.daily.length - 1, Math.floor(y / rowPitch)))
            }

            HoverHandler {
                id: weekHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: eventPoint => root.select(week.rowAt(eventPoint.position.y))
            }

            Repeater {
                model: Weather.daily
                delegate: Item {
                    id: day
                    required property var modelData
                    required property int index
                    readonly property bool picked: root.sel === day.index
                    width: parent.width
                    height: 22

                    // Клик — показать день в главной карточке (обработчики — у week)
                    Rectangle {
                        x: -6
                        width: parent.width + 12
                        height: parent.height
                        radius: 6
                        color: day.picked ? Theme.surface0
                             : week.hoverIdx === day.index ? Theme.alpha(Theme.surface0, 0.5) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    // День, который сейчас на ленте часов
                    Rectangle {
                        x: -4
                        width: 3
                        height: 12
                        radius: 1.5
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.mix(Theme.gradStart, Theme.gradEnd, 0.5)
                        opacity: hours.viewDay === day.index ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                    }

                    Text {
                        id: dayName
                        width: 66
                        anchors.verticalCenter: parent.verticalCenter
                        text: day.modelData.name
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: day.picked ? Theme.text : Theme.subtext0
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
                            gradient: OkGradient {
                                orientation: Gradient.Horizontal
                                from: Theme.mix(Theme.sky, Theme.peach, week.pos(day.modelData.min))
                                to: Theme.mix(Theme.sky, Theme.peach, week.pos(day.modelData.max))
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
