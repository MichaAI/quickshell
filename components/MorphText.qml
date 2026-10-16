pragma ComponentBehavior: Bound
import QtQuick
import "../config"
import "../assets/digits/Digits.js" as Digits

// Числа, у которых цифры перетекают одна в другую с одинаковой толщиной
// штриха на каждом кадре. Символ — осевые линии, обведённые круглой
// кистью (tools/digits.py); при смене цифры линии плавно переходят в
// линии новой по заранее подобранным парам, а кисть всё та же. Ширина
// символа тоже плывёт. Строку с символами вне «0-9:%.,+-−°/ » рисует
// обычный Text. Заливка — градиент color → colorTo по всей строке, в OkLab.
Item {
    id: root

    property string text: ""
    // neofolia | mono | monoBold | monoBoldItalic
    property string font: "mono"
    property real pixelSize: Theme.fontSize
    property color color: Theme.text
    property color colorTo: color
    property real outlineWidth: 0
    property color outlineColor: Theme.base
    property int duration: 380

    readonly property var f: Digits.fonts[font]
    readonly property real h: f.height * pixelSize          // высота рамки символа
    readonly property bool supported: text.split("").every(c => f.chars[c] !== undefined)

    // Целые размеры: иначе при центровке строка встаёт на полпикселя и мылится
    implicitWidth: supported ? Math.ceil(row.width) : fallback.implicitWidth
    implicitHeight: supported ? Math.ceil(h) : fallback.implicitHeight
    baselineOffset: supported ? f.baseline * h : fallback.baselineOffset

    // Пары штрихов для перехода a → b: [[точки «откуда», точки «куда»,
    // замкнут, радиус кисти «откуда», «куда»], …]. Точки — плоский массив
    // x, y в долях h; у точек («:», «.») свой радиус, у штрихов — общий
    function plan(a, b) {
        const ca = f.chars[a], cb = f.chars[b]
        const rad = s => s?.r ?? f.radius
        if (a === b)
            return ca.strokes.map(s => [s.pts, s.pts, s.closed, rad(s), rad(s)])
        const n = (ca.strokes[0] ?? cb.strokes[0])?.pts.length ?? 0
        const point = p => { const r = []; for (let k = 0; k < n; k += 2) r.push(p[0], p[1]); return r }
        // Точки ломаной по дробным индексам выравнивания (DTW у пар цифр)
        const at = (pts, us) => {
            const m = pts.length / 2, out = []
            for (const u of us) {
                const i = Math.min(Math.floor(u), m - 2), fr = u - i
                out.push(pts[2 * i] * (1 - fr) + pts[2 * i + 2] * fr,
                         pts[2 * i + 1] * (1 - fr) + pts[2 * i + 3] * fr)
            }
            return out
        }
        return (f.pairs[a + b] ?? []).map(([ia, ib, shift, rev, p, ua, ub]) => {
            // Штрих без пары стягивается в точку на другом символе
            const pa = ia >= 0 ? ca.strokes[ia].pts : point(p)
            let pb = ib >= 0 ? cb.strokes[ib].pts : point(p)
            // Тот же обход, что выбрал tools/digits.py: сдвиг начала петли и направление
            if (ib >= 0 && (shift || rev)) {
                const m = pb.length / 2, out = []
                for (let k = 0; k < m; k++) {
                    const j = (shift + (rev ? m - 1 - k : k)) % m
                    out.push(pb[2 * j], pb[2 * j + 1])
                }
                pb = out
            }
            const warped = ua ? [at(pa, ua), at(pb, ub)] : [pa, pb]
            const sa = ca.strokes[ia], sb = cb.strokes[ib]
            const closed = ia >= 0 && sa.closed && ib >= 0 && sb.closed
            return [warped[0], warped[1], closed, rad(ia >= 0 ? sa : sb), rad(ib >= 0 ? sb : sa)]
        })
    }

    Row {
        id: row
        visible: root.supported

        Repeater {
            model: root.supported ? root.text.length : 0

            Item {
                id: slot
                required property int index
                readonly property string ch: root.text.charAt(index)
                property string from: ch
                property string to: ch
                property real t: 1
                property var steps: root.plan(ch, ch)

                // Новая цифра: перетекаем из той, что сейчас ближе
                onChChanged: {
                    from = t < 0.5 ? from : to
                    to = ch
                    steps = root.plan(from, to)
                    t = 0
                    morph.restart()
                }
                NumberAnimation {
                    id: morph
                    target: slot; property: "t"; to: 1
                    duration: root.duration; easing.type: Easing.InOutCubic
                }

                readonly property real adv: root.f.chars[from].adv + (root.f.chars[to].adv - root.f.chars[from].adv) * t
                width: root.h * adv
                height: root.h

                Canvas {
                    id: canvas
                    // Рисуем в своём потоке: на лок часы не тормозят его появление
                    renderStrategy: Canvas.Threaded
                    // Запас под кисть, обводку и наклон курсива
                    readonly property real pad: root.h * (root.f.radius + 0.3) + root.outlineWidth
                    // Холст — на целых пикселях, хоть символ и стоит на дробной
                    // ширине соседей: текстура со сдвигом на полпикселя мылится.
                    // offX, offY — где внутри холста начало символа
                    x: Math.floor(slot.x - pad + 0.5) - slot.x
                    y: -Math.ceil(pad)
                    readonly property real offX: -x
                    readonly property real offY: -y
                    width: Math.ceil(slot.width + 2 * pad + 1)
                    height: Math.ceil(root.h) + 2 * Math.ceil(pad)

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const h = root.h, t = slot.t
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        const trace = (pa, pb, closed) => {
                            const n = pa.length / 2
                            const px = k => offX + (pa[2 * k] + (pb[2 * k] - pa[2 * k]) * t) * h
                            const py = k => offY + (pa[2 * k + 1] + (pb[2 * k + 1] - pa[2 * k + 1]) * t) * h
                            ctx.beginPath()
                            ctx.moveTo(px(0), py(0))
                            // Вся линия в полпикселя — это точка («:», «.»): круг кисти
                            let span = 0
                            for (let k = 1; k < n; k++)
                                span = Math.max(span, Math.abs(px(k) - px(0)), Math.abs(py(k) - py(0)))
                            if (span < 0.5) {
                                ctx.lineTo(px(0) + 0.01, py(0))
                                return
                            }
                            // Гладко: квадратичные кривые через середины отрезков
                            for (let k = 1; k < n - 1; k++)
                                ctx.quadraticCurveTo(px(k), py(k), (px(k) + px(k + 1)) / 2, (py(k) + py(k + 1)) / 2)
                            ctx.lineTo(px(n - 1), py(n - 1))
                            if (closed)
                                ctx.closePath()
                        }
                        const width = (ra, rb) => 2 * h * (ra + (rb - ra) * t)
                        if (root.outlineWidth > 0) {
                            ctx.strokeStyle = root.outlineColor
                            for (const [pa, pb, closed, ra, rb] of slot.steps) {
                                ctx.lineWidth = width(ra, rb) + 2 * root.outlineWidth
                                trace(pa, pb, closed); ctx.stroke()
                            }
                        }
                        // Градиент по всей строке, а не по символу
                        const g = ctx.createLinearGradient(offX - slot.x, 0, offX - slot.x + row.width, 0)
                        Theme.okStops(g, root.color, root.colorTo)
                        ctx.strokeStyle = g
                        for (const [pa, pb, closed, ra, rb] of slot.steps) {
                            ctx.lineWidth = width(ra, rb)
                            trace(pa, pb, closed); ctx.stroke()
                        }
                    }

                    Connections {
                        target: slot
                        function onTChanged() { canvas.requestPaint() }
                        function onStepsChanged() { canvas.requestPaint() }
                        function onXChanged() { canvas.requestPaint() }
                    }
                    Connections {
                        target: root
                        function onColorChanged() { canvas.requestPaint() }
                        function onColorToChanged() { canvas.requestPaint() }
                        function onOutlineColorChanged() { canvas.requestPaint() }
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                }
            }
        }
    }

    Text {
        id: fallback
        visible: !root.supported
        text: root.text
        font.family: root.font === "neofolia" ? Theme.displayFont : Theme.font
        font.pixelSize: root.pixelSize
        font.italic: root.font.endsWith("Italic")
        font.weight: root.font.startsWith("monoBold") ? Font.Bold : Font.Normal
        color: root.color
    }
}
