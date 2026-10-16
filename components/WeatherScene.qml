pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../config"

// Живое небо в духе Breezy Weather: градиент по погоде и времени суток,
// солнце с дышащими ореолами или луна со звёздами, плывущие облака,
// дождь, снег, туман и молнии. Ветер косит дождь и снег и гонит облака.
// Обрезку по скруглению делает родитель.
Item {
    id: root

    property string kind: "clear"   // clear partly cloudy fog drizzle rain snow thunder
    property bool isDay: true
    property real wind: 0           // м/с
    property real windDir: 0        // откуда дует, градусы

    // Ветер поперёк взгляда: + — дует вправо (на восток)
    readonly property real windX: wind * Math.sin((windDir + 180) * Math.PI / 180)
    // Наклон дождя и снега, градусы: + — низ капли правее верха
    readonly property real tilt: Math.max(-35, Math.min(35, windX * 3))
    readonly property real slope: Math.tan(tilt * Math.PI / 180)

    // Для PopoutReveal: проявлять сцену целиком, не разбирая на частицы
    readonly property bool revealWhole: true

    readonly property bool wet: kind === "drizzle" || kind === "rain" || kind === "thunder"
    readonly property bool overcast: wet || kind === "cloudy" || kind === "snow" || kind === "fog"
    // В пасмурную погоду светило не пропадает, а еле проглядывает за облаками
    readonly property bool dimLight: kind === "cloudy"
    readonly property bool showSun: isDay && (kind === "clear" || kind === "partly" || dimLight)
    readonly property bool showMoon: !isDay && (kind === "clear" || kind === "partly" || dimLight)
    readonly property real lightOpacity: dimLight ? 0.3 : 1

    // Небо: [верх, низ]. Достаточно тёмное, чтобы светлый текст читался
    readonly property var sky: {
        if (kind === "thunder") return ["#1f1a2e", "#3d3552"]
        if (wet) return isDay ? ["#34445a", "#5a6b80"] : ["#151b29", "#2b3446"]
        if (kind === "snow") return isDay ? ["#4d6283", "#8597b3"] : ["#1b2133", "#39425a"]
        if (kind === "fog") return isDay ? ["#4f5664", "#7b828f"] : ["#1d1f28", "#3a3d4a"]
        if (kind === "cloudy") return isDay ? ["#45556c", "#71839b"] : ["#181c2a", "#323849"]
        return isDay ? ["#2a5a9c", "#5d97d2"] : ["#0c1026", "#262c58"]
    }

    // Детерминированный «рандом», чтобы частицы не прыгали при пересоздании
    function rnd(i, salt) {
        const x = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453
        return x - Math.floor(x)
    }

    Rectangle {
        anchors.fill: parent
        gradient: OkGradient {
            from: root.sky[0]
            to: root.sky[1]
            Behavior on from { ColorAnimation { duration: 600 } }
            Behavior on to { ColorAnimation { duration: 600 } }
        }
    }

    // ===== Звёзды =====
    Repeater {
        model: root.isDay || root.overcast ? 0 : 28
        delegate: Rectangle {
            id: star
            required property int index
            readonly property real s: 1 + root.rnd(star.index, 3) * 1.6
            x: root.rnd(star.index, 1) * root.width
            y: root.rnd(star.index, 2) * root.height * 0.75
            width: s; height: s; radius: s / 2
            color: "white"
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                PauseAnimation { duration: root.rnd(star.index, 4) * 3000 }
                NumberAnimation { to: 0.15; duration: 900 + root.rnd(star.index, 5) * 1400; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.85; duration: 900 + root.rnd(star.index, 6) * 1400; easing.type: Easing.InOutSine }
            }
        }
    }

    // ===== Солнце: ядро и дышащие ореолы =====
    Item {
        id: sun
        visible: root.showSun
        opacity: root.lightOpacity
        Behavior on opacity { NumberAnimation { duration: 600 } }
        width: 52; height: 52
        x: root.width - 80
        y: 18

        Repeater {
            model: 3
            delegate: Rectangle {
                id: halo
                required property int index
                anchors.centerIn: parent
                width: parent.width * (1.6 + halo.index * 0.75)
                height: width
                radius: width / 2
                color: Theme.alpha(Theme.yellow, 0.10 - halo.index * 0.025)
                SequentialAnimation on scale {
                    running: sun.visible
                    loops: Animation.Infinite
                    PauseAnimation { duration: halo.index * 500 }
                    NumberAnimation { from: 0.92; to: 1.08; duration: 2600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.08; to: 0.92; duration: 2600; easing.type: Easing.InOutSine }
                }
            }
        }

        // Лучи медленно вращаются
        Item {
            anchors.fill: parent
            RotationAnimation on rotation {
                running: sun.visible
                from: 0; to: 360
                duration: 60000
                loops: Animation.Infinite
            }
            Repeater {
                model: 12
                delegate: Rectangle {
                    id: ray
                    required property int index
                    x: parent.width / 2 - width / 2
                    y: -14
                    width: 3; height: 10; radius: 1.5
                    color: Theme.alpha(Theme.yellow, 0.55)
                    transform: Rotation {
                        origin.x: 1.5
                        origin.y: 26 + 14
                        angle: ray.index * 30
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: OkGradient {
                from: "#fff3c4"
                to: Theme.peach
            }
        }
    }

    // ===== Луна =====
    Item {
        id: moon
        visible: root.showMoon
        opacity: root.lightOpacity
        Behavior on opacity { NumberAnimation { duration: 600 } }
        width: 40; height: 40
        x: root.width - 74
        y: 20

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 2.6; height: width; radius: width / 2
            color: Theme.alpha(Theme.lavender, 0.08)
            SequentialAnimation on scale {
                running: moon.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0.9; to: 1.1; duration: 3200; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.1; to: 0.9; duration: 3200; easing.type: Easing.InOutSine }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#e8e6f5"
        }
        // Кратеры
        Repeater {
            model: [[9, 10, 8], [22, 20, 6], [14, 25, 4]]
            delegate: Rectangle {
                id: crater
                required property var modelData
                x: crater.modelData[0]; y: crater.modelData[1]
                width: crater.modelData[2]; height: width; radius: width / 2
                color: "#cfcbe3"
            }
        }
    }

    // ===== Облака =====
    component Cloud: Item {
        id: cloud
        property color tint: "white"
        // Круги рисуются непрозрачными, прозрачность — всему облаку разом,
        // иначе на стыках кругов темнеет
        property real alpha: 0.2
        opacity: alpha
        layer.enabled: true
        // Сглаживание слоя: без него текстура липнет к целым пикселям,
        // и медленное облако ползёт рывками
        layer.smooth: true
        property real phase: 0          // начальная позиция, 0…1
        property int period: 60000      // полный проход, мс
        property int dir: 1             // 1 — вправо, -1 — влево
        property real span: 0           // ширина неба
        property real t
        readonly property real p: (t + phase) % 1

        width: 120; height: 48
        x: dir > 0 ? -width + (span + width) * p : span - (span + width) * p

        NumberAnimation on t {
            from: 0; to: 1
            duration: cloud.period
            loops: Animation.Infinite
        }

        Rectangle { x: 0; y: parent.height * 0.45; width: parent.width; height: parent.height * 0.55; radius: height / 2; color: cloud.tint }
        Rectangle { x: parent.width * 0.14; y: parent.height * 0.18; width: parent.width * 0.38; height: width; radius: width / 2; color: cloud.tint }
        Rectangle { x: parent.width * 0.40; y: 0; width: parent.width * 0.42; height: width; radius: width / 2; color: cloud.tint }
    }

    readonly property int cloudCount: kind === "partly" ? 2 : (overcast ? 5 : 0)

    Repeater {
        model: root.cloudCount
        delegate: Cloud {
            id: skyCloud
            required property int index
            readonly property real depth: root.rnd(skyCloud.index, 7)
            // Своя полоса по высоте, перемешанная относительно порядка по x,
            // чтобы соседи по небу не шли одной линией
            readonly property int lane: (skyCloud.index * 3) % root.cloudCount
            width: 80 + depth * 70
            height: width * 0.4
            y: -8 + (lane + root.rnd(skyCloud.index, 8) * 0.6) / root.cloudCount
                 * root.height * (root.kind === "partly" ? 0.45 : 0.5)
            span: root.width
            // Равномерно по ширине с небольшим разбросом, а не как выпадет
            phase: (skyCloud.index + root.rnd(skyCloud.index, 9) * 0.5) / root.cloudCount
            // Скорости близкие: сильно разные нагоняли друг друга и сбивались в кучу
            // Ветер гонит быстрее и в свою сторону
            period: (62000 - depth * 12000) / (1 + Math.abs(root.windX) / 4)
            dir: root.windX < -0.5 ? -1 : 1
            tint: root.wet ? (root.isDay ? "#c3cede" : "#8f9ab0") : "white"
            alpha: root.kind === "partly" ? (root.isDay ? 0.22 : 0.1) + depth * 0.14
                 : root.wet ? 0.12 + depth * 0.12
                 : (root.isDay ? 0.12 : 0.07) + depth * 0.12
        }
    }

    // ===== Туман: полупрозрачные полосы качаются вбок =====
    Repeater {
        model: root.kind === "fog" ? 5 : 0
        delegate: Rectangle {
            id: fogBand
            required property int index
            property real t
            width: root.width * 1.4
            height: 18 + root.rnd(fogBand.index, 10) * 18
            radius: height / 2
            y: root.height * (0.2 + fogBand.index * 0.16)
            x: -root.width * 0.2 + Math.sin(t * Math.PI * 2) * root.width * 0.12
            color: Qt.rgba(1, 1, 1, 0.07 + root.rnd(fogBand.index, 11) * 0.08)
            NumberAnimation on t {
                from: root.rnd(fogBand.index, 12); to: root.rnd(fogBand.index, 12) + 1
                duration: 9000 + root.rnd(fogBand.index, 13) * 6000
                loops: Animation.Infinite
            }
        }
    }

    // ===== Дождь: косые капли разбиваются о низ карточки =====
    // Капля летит, пока не коснётся низа, а потом брызгает: две капельки
    // по дуге в стороны и короткая черта лужицы. Всё плоское
    readonly property int splashMs: 420
    Repeater {
        model: root.kind === "drizzle" ? 30 : (root.kind === "rain" ? 70 : (root.kind === "thunder" ? 90 : 0))
        delegate: Item {
            id: drop
            required property int index
            property real t
            readonly property real phase: (t + root.rnd(drop.index, 14)) % 1
            readonly property real len: root.kind === "drizzle" ? 7 : 11 + root.rnd(drop.index, 16) * 7
            readonly property int fallMs: (root.kind === "drizzle" ? 1100 : 650) + root.rnd(drop.index, 18) * 300
            readonly property real split: fallMs / (fallMs + root.splashMs)
            readonly property real fall: Math.min(1, phase / split)
            readonly property real s: phase < split ? -1 : (phase - split) / (1 - split)
            readonly property real path: root.height - drop.len + 20
            // Старт выше и с запасом против ветра, чтобы снос не оголял край
            readonly property real drift: path * root.slope
            readonly property real x0: -Math.max(0, drift) - 10 + root.rnd(drop.index, 15) * (root.width + Math.abs(drift) + 20)
            readonly property real hitX: x0 + drift + 0.75 + drop.len / 2 * Math.sin(root.tilt * Math.PI / 180)
            readonly property real alpha: 0.25 + root.rnd(drop.index, 17) * 0.3
            readonly property color tint: Qt.rgba(0.86, 0.9, 0.96, 1)

            Rectangle {
                visible: drop.s < 0
                width: 1.5
                height: drop.len
                radius: 0.75
                rotation: -root.tilt
                x: drop.x0 + drop.fall * drop.drift
                y: -20 + drop.fall * drop.path
                color: drop.tint
                opacity: drop.alpha
            }

            // Брызги: капельки в стороны по дуге
            Repeater {
                model: 3
                Rectangle {
                    id: bit
                    required property int index
                    // Влево, вправо и третья — куда повезёт, пониже
                    readonly property real dir: bit.index === 0 ? -1 : bit.index === 1 ? 1 : root.rnd(drop.index, 27) - 0.5
                    readonly property real vx: 5 + root.rnd(drop.index * 3 + bit.index, 25) * 7
                    readonly property real vy: (bit.index === 2 ? 4 : 7) + root.rnd(drop.index * 3 + bit.index, 26) * 7
                    visible: drop.s >= 0
                    width: 2.5; height: 2.5; radius: 1.25
                    x: drop.hitX + bit.dir * bit.vx * drop.s - 1.25
                    y: root.height - 2.5 - 4 * bit.vy * drop.s * (1 - drop.s)
                    scale: 1 - 0.4 * drop.s
                    color: drop.tint
                    opacity: Math.min(1, drop.alpha + 0.3) * (1 - drop.s * drop.s)
                }
            }
            // Лужица: черта расходится и тает
            Rectangle {
                visible: drop.s >= 0
                width: 3 + 14 * drop.s
                height: 2
                radius: 1
                x: drop.hitX - width / 2
                y: root.height - 2
                color: drop.tint
                opacity: Math.min(1, drop.alpha + 0.2) * (1 - drop.s)
            }

            NumberAnimation on t {
                from: 0; to: 1
                duration: drop.fallMs + root.splashMs
                loops: Animation.Infinite
            }
        }
    }

    // ===== Снег: хлопья падают и покачиваются =====
    Repeater {
        model: root.kind === "snow" ? 50 : 0
        delegate: Rectangle {
            id: flake
            required property int index
            property real t
            readonly property real p: (t + root.rnd(flake.index, 19)) % 1
            readonly property real s: 2 + root.rnd(flake.index, 20) * 3.5
            width: s; height: s; radius: s / 2
            readonly property real drift: (root.height + 20) * root.slope
            x: -Math.max(0, drift) + root.rnd(flake.index, 21) * (root.width + Math.abs(drift))
               + p * drift + Math.sin((p * 3 + root.rnd(flake.index, 22)) * Math.PI * 2) * 8
            y: -10 + p * (root.height + 20)
            color: Qt.rgba(1, 1, 1, 0.5 + root.rnd(flake.index, 23) * 0.4)
            NumberAnimation on t {
                from: 0; to: 1
                duration: 6000 + root.rnd(flake.index, 24) * 5000
                loops: Animation.Infinite
            }
        }
    }

    // ===== Гроза: молния растёт, как в замедленной съёмке =====
    // Каждый раз новая: лидер ступеньками ползёт вниз и ветвится, ветки
    // отстают и глохнут. Дошёл до низа — главный канал разгорается и всё
    // плавно гаснет. Экран не вспыхивает
    Canvas {
        id: lightning
        anchors.fill: parent
        visible: root.kind === "thunder"

        property var segs: []          // [x1, y1, x2, y2, путь до начала, длина, главный, ветка]
        property real total: 0         // длина главного канала
        property real front: 0         // докуда дорос лидер
        property real glow: 0          // разгорание после касания
        property real fade: 1
        property real stepWait: 0

        function strike() {
            const segs = []
            let chains = 0
            const grow = (x, y, bias, d, depth, main) => {
                const chain = chains++
                let steps = main ? 1000 : 3 + Math.floor(Math.random() * (8 - depth * 2))
                while (steps-- > 0 && y < height) {
                    const nx = x + (Math.random() - 0.5) * 12 + bias
                    const ny = y + 5 + Math.random() * 7
                    const len = Math.hypot(nx - x, ny - y)
                    segs.push([x, y, nx, ny, d, len, main, chain])
                    if (depth < 2 && Math.random() < (main ? 0.22 : 0.12))
                        grow(nx, ny, (Math.random() < 0.5 ? -1 : 1) * (4 + Math.random() * 4), d + len, depth + 1, false)
                    x = nx; y = ny; d += len
                    if (main) total = d
                }
            }
            total = 0
            grow(width * (0.3 + Math.random() * 0.45), 14, 0, 0, 0, true)
            lightning.segs = segs
            front = 0; glow = 0; fade = 1; stepWait = 0
            afterglow.stop()
        }

        // Лидер: рывок на 7–12 px каждые ~45 мс
        FrameAnimation {
            running: lightning.visible && lightning.segs.length > 0 && lightning.front < lightning.total
            onTriggered: {
                lightning.stepWait -= frameTime
                if (lightning.stepWait > 0)
                    return
                lightning.stepWait = 0.035 + Math.random() * 0.03
                lightning.front = Math.min(lightning.total, lightning.front + 7 + Math.random() * 5)
                lightning.requestPaint()
            }
        }

        onFrontChanged: if (front >= total && total > 0) afterglow.restart()
        SequentialAnimation {
            id: afterglow
            NumberAnimation { target: lightning; property: "glow"; to: 1; duration: 140; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 120 }
            NumberAnimation { target: lightning; property: "fade"; to: 0; duration: 900; easing.type: Easing.InOutQuad }
            ScriptAction { script: { lightning.segs = []; lightning.requestPaint() } }
        }
        onGlowChanged: requestPaint()
        onFadeChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (segs.length === 0 || fade <= 0)
                return
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            // Каждая ветка — один путь, иначе на стыках отрезков свечение
            // копится бусинами
            const paths = {}
            for (const g of segs) {
                if (g[4] >= front)
                    continue
                const k = Math.min(1, (front - g[4]) / g[5])
                const c = paths[g[7]] ?? (paths[g[7]] = { main: g[6], pts: [[g[0], g[1]]] })
                c.pts.push([g[0] + (g[2] - g[0]) * k, g[1] + (g[3] - g[1]) * k])
            }
            // Два прохода: мягкое свечение и ядро
            for (const pass of [0, 1]) {
                for (const c of Object.values(paths)) {
                    // Ветки после касания гаснут быстрее канала
                    const a = fade * (c.main ? 1 : Math.max(0, 1 - glow * 0.6))
                    if (pass === 0) {
                        ctx.strokeStyle = Qt.rgba(0.8, 0.78, 1, (c.main ? 0.12 + 0.22 * glow : 0.08) * a)
                        ctx.lineWidth = c.main ? 4 + 5 * glow : 3
                    } else {
                        ctx.strokeStyle = Qt.rgba(1, 0.97, 0.86, (c.main ? 0.7 + 0.3 * glow : 0.55) * a)
                        ctx.lineWidth = c.main ? 1.3 + 1.2 * glow : 0.9
                    }
                    ctx.beginPath()
                    ctx.moveTo(c.pts[0][0], c.pts[0][1])
                    for (let i = 1; i < c.pts.length; i++)
                        ctx.lineTo(c.pts[i][0], c.pts[i][1])
                    ctx.stroke()
                }
            }
        }

        Timer {
            running: lightning.visible
            interval: 2500
            repeat: true
            onTriggered: {
                lightning.strike()
                interval = 3500 + Math.random() * 5500
            }
        }
    }

    // Затемнение слева и снизу под текст
    Rectangle {
        anchors.fill: parent
        gradient: OkGradient {
            orientation: Gradient.Horizontal
            from: Qt.rgba(0, 0, 0, 0.22)
            to: "transparent"
            end: 0.6
        }
    }
    Rectangle {
        anchors.fill: parent
        gradient: OkGradient {
            from: "transparent"
            to: Qt.rgba(0, 0, 0, 0.32)
            start: 0.35
        }
    }
}
