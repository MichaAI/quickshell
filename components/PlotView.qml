import QtQuick
import "../config"

// График по готовым линиям из Calc.plot(): {series: [{label, xs, ys, …}],
// opts}. Оси, сетка, первая линия — градиентом темы, остальные — цветами
// Theme.series; стили, сглаживание и логарифмические оси — как у qalc.
// Под курсором — значения всех линий.
Item {
    id: root

    property var plot: null

    readonly property var opts: plot ? plot.opts : ({})
    readonly property var series: plot ? plot.series : []
    readonly property bool polar: opts.style === "polar"
    readonly property real lw: opts.linewidth > 0 ? opts.linewidth : 2

    // Легенда: у нескольких линий — полосой снизу, по просьбе — в углу
    readonly property string legendAt: opts.legend === "none" ? ""
        : opts.legend ? (opts.legend === "outside" ? "below" : opts.legend)
        : series.length > 1 ? "below" : ""

    // Конечное число; null (из JSON и т.п.) — нет, хотя isFinite(null) === true
    function fin(v) { return typeof v === "number" && isFinite(v) }

    function seriesColor(i) {
        if (opts.mono) return Theme.text
        return i === 0 ? Theme.gradStart : Theme.series[(i - 1) % Theme.series.length]
    }
    // Мнимая часть — цветом своей действительной
    function colorIndex(i) {
        let k = -1
        for (let j = 0; j <= i; j++)
            if (!series[j].im) k++
        return k
    }

    // Логарифмические оси: всё, что ≤ 0, выпадает
    function tx(x) { return opts.xlog ? (x > 0 ? Math.log10(x) : NaN) : x }
    function ty(y) { return opts.ylog ? (y > 0 ? Math.log10(y) : NaN) : y }

    // Диапазоны в «осевых» единицах (после логарифма)
    readonly property var xRange: {
        const xs = []
        for (const s of series)
            for (let i = 0; i < s.xs.length; i++)
                if (root.fin(s.ys[i]) && root.fin(tx(s.xs[i]))) xs.push(tx(s.xs[i]))
        let lo, hi
        if (!polar && series.some(s => s.fn)) {
            lo = tx(plot.min); hi = tx(plot.max)
            if (!root.fin(lo)) lo = Math.min(...xs)
        }
        if (polar || lo === undefined) {
            // Данные: по точкам, с полями
            if (xs.length === 0) return [0, 1]
            lo = Math.min(...xs); hi = Math.max(...xs)
            if (hi - lo < 1e-9) { lo -= 1; hi += 1 }
            // Столбцам — полшага по краям, иначе крайние обрезаны
            const bars = ["boxes", "candlesticks", "histogram"].includes(opts.style)
            const n = Math.max(...series.map(s => s.xs.length))
            const pad = bars && n > 1 ? (hi - lo) / (n - 1) / 2 : (hi - lo) * (polar ? 0.08 : 0.04)
            return [lo - pad, hi + pad]
        }
        return [lo, hi]
    }

    // По y — без выбросов (tan(x) у асимптот), с полями; ymin/ymax — как задано
    readonly property var yRange: {
        const v = []
        for (const s of series)
            for (const y of s.ys) {
                const t = ty(y)
                if (root.fin(t)) v.push(t)
            }
        v.sort((a, b) => a - b)
        let lo, hi
        if (v.length === 0) { lo = -1; hi = 1 }
        else if (series.every(s => s.data)) { lo = v[0]; hi = v[v.length - 1] }
        else { lo = v[Math.floor(v.length * 0.02)]; hi = v[Math.ceil(v.length * 0.98) - 1] }
        // Столбцы растут от нуля
        if ((opts.style === "boxes" || opts.style === "candlesticks") && !opts.ylog) {
            lo = Math.min(lo, 0); hi = Math.max(hi, 0)
        }
        if (hi - lo < 1e-9) { lo -= 1; hi += 1 }
        const pad = (hi - lo) * 0.08
        lo -= pad; hi += pad
        const yLo = ty(opts.yLo), yHi = ty(opts.yHi)
        if (root.fin(yLo)) lo = yLo
        if (root.fin(yHi)) hi = yHi
        if (hi <= lo) hi = lo + 1
        return [lo, hi]
    }

    // Полярный — в одном масштабе по осям, иначе круг станет эллипсом
    readonly property var view: {
        if (!polar || area.width <= 0 || area.height <= 0) return { x: xRange, y: yRange }
        let [x0, x1] = xRange, [y0, y1] = yRange
        const k = Math.max((x1 - x0) / area.width, (y1 - y0) / area.height)
        const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
        return { x: [cx - k * area.width / 2, cx + k * area.width / 2],
                 y: [cy - k * area.height / 2, cy + k * area.height / 2] }
    }

    function px(x) { return (tx(x) - view.x[0]) / (view.x[1] - view.x[0]) * area.width }
    function py(y) { return area.height - (ty(y) - view.y[0]) / (view.y[1] - view.y[0]) * area.height }

    function fmt(v) {
        const a = Math.abs(v)
        if (a !== 0 && (a >= 1e5 || a < 1e-3)) return v.toExponential(2)
        return String(Math.round(v * 1000) / 1000)
    }
    // Подпись диапазона: на логарифмической оси — обратно в числа
    function fmtY(t) { return fmt(opts.ylog ? Math.pow(10, t) : t) }

    onPlotChanged: canvas.requestPaint()

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.alpha(Theme.crust, 0.6)
    }

    // Поле графика; легенда «below» — полосой под ним
    Item {
        id: area
        anchors.fill: parent
        anchors.bottomMargin: root.legendAt === "below" ? legendRow.height + 8 : 0
        onWidthChanged: canvas.requestPaint()
        onHeightChanged: canvas.requestPaint()

        Canvas {
            id: canvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                if (!root.plot || width <= 0 || height <= 0) return
                const w = width, h = height

                // Сетка
                ctx.strokeStyle = Theme.alpha(Theme.surface1, 0.5)
                ctx.lineWidth = 1
                if (root.opts.grid !== false) {
                    for (let i = 1; i < 8; i++) {
                        ctx.beginPath(); ctx.moveTo(w * i / 8, 0); ctx.lineTo(w * i / 8, h); ctx.stroke()
                    }
                    for (let i = 1; i < 4; i++) {
                        ctx.beginPath(); ctx.moveTo(0, h * i / 4); ctx.lineTo(w, h * i / 4); ctx.stroke()
                    }
                }

                // Оси, если попадают в окно (на логарифмической оси нуля нет)
                ctx.strokeStyle = Theme.overlay0
                const x0 = root.opts.xlog ? NaN : root.px(0), y0 = root.opts.ylog ? NaN : root.py(0)
                if (x0 >= 0 && x0 <= w) { ctx.beginPath(); ctx.moveTo(x0, 0); ctx.lineTo(x0, h); ctx.stroke() }
                if (y0 >= 0 && y0 <= h) { ctx.beginPath(); ctx.moveTo(0, y0); ctx.lineTo(w, y0); ctx.stroke() }

                // Последней рисуем первую — градиентная главная линия сверху
                for (let i = root.series.length - 1; i >= 0; i--)
                    drawSeries(ctx, root.series[i], root.colorIndex(i), w, h)
            }

            function drawSeries(ctx, s, ci, w, h) {
                const style = root.opts.style
                const color = ci === 0 && !root.opts.mono
                    ? Theme.okStops(ctx.createLinearGradient(0, 0, w, 0), Theme.gradStart, Theme.gradEnd)
                    : root.seriesColor(ci)
                ctx.strokeStyle = color
                ctx.fillStyle = color
                ctx.lineWidth = root.lw
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                // Пунктир: мнимая часть, а в mono — чтобы различать линии
                const dashes = [[], [6, 4], [2, 4], [10, 3, 2, 3], [1, 3]]
                const dash = s.im ? [5, 4] : root.opts.mono ? dashes[ci % dashes.length] : []
                if (ctx.setLineDash) ctx.setLineDash(dash.map(d => d * root.lw / 2))

                // Точки на экране, разбитые на куски: NaN и (у функций) скачки
                // через всю высоту — асимптоты, их не соединяем
                const runs = []
                let run = []
                for (let i = 0; i < s.ys.length; i++) {
                    const X = root.px(s.xs[i]), Y = root.py(s.ys[i])
                    if (!root.fin(s.ys[i]) || !root.fin(X) || !root.fin(Y)) {
                        if (run.length) runs.push(run)
                        run = []
                        continue
                    }
                    if (s.fn && !root.polar && run.length && Math.abs(Y - run[run.length - 1][1]) > h * 1.5) {
                        runs.push(run)
                        run = []
                    }
                    run.push([X, Y])
                }
                if (run.length) runs.push(run)

                const lines = style === "lines" || style === "linespoints" || style === "polar"
                if (lines)
                    for (const r of runs) path(ctx, r)
                if (style === "steps" || style === "histogram")
                    for (const r of runs) steps(ctx, r, style === "histogram")
                if (style === "boxes" || style === "candlesticks")
                    for (const r of runs) boxes(ctx, r, h)
                if (style === "points" || style === "linespoints" || style === "dots") {
                    const rad = style === "dots" ? Math.max(0.75, root.lw / 3) : root.lw + 0.5
                    for (const r of runs)
                        for (const [X, Y] of r) {
                            ctx.beginPath()
                            ctx.arc(X, Y, rad, 0, Math.PI * 2)
                            ctx.fill()
                        }
                }
                if (ctx.setLineDash) ctx.setLineDash([])
            }

            // Ломаная или сглаженная: splines — через точки (Catmull-Rom),
            // bezier — по середине отрезков, точки — опорные
            function path(ctx, r) {
                ctx.beginPath()
                ctx.moveTo(r[0][0], r[0][1])
                const smooth = root.opts.smooth
                if (r.length < 3 || smooth === "none" || !smooth) {
                    for (let i = 1; i < r.length; i++) ctx.lineTo(r[i][0], r[i][1])
                } else if (smooth === "bezier") {
                    for (let i = 1; i < r.length - 1; i++)
                        ctx.quadraticCurveTo(r[i][0], r[i][1],
                            (r[i][0] + r[i + 1][0]) / 2, (r[i][1] + r[i + 1][1]) / 2)
                    ctx.lineTo(r[r.length - 1][0], r[r.length - 1][1])
                } else {
                    for (let i = 0; i < r.length - 1; i++) {
                        const p0 = r[Math.max(0, i - 1)], p1 = r[i], p2 = r[i + 1], p3 = r[Math.min(r.length - 1, i + 2)]
                        ctx.bezierCurveTo(p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6,
                                          p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6,
                                          p2[0], p2[1])
                    }
                }
                ctx.stroke()
            }

            // steps — ступенька после точки; histogram — с центром в точке
            function steps(ctx, r, centered) {
                ctx.beginPath()
                for (let i = 0; i < r.length; i++) {
                    const [X, Y] = r[i]
                    const prev = r[i - 1], next = r[i + 1]
                    if (centered) {
                        const a = prev ? (prev[0] + X) / 2 : X - (next ? (next[0] - X) / 2 : 4)
                        const b = next ? (next[0] + X) / 2 : X + (prev ? (X - prev[0]) / 2 : 4)
                        if (i === 0) ctx.moveTo(a, Y)
                        else ctx.lineTo(a, Y)
                        ctx.lineTo(b, Y)
                    } else {
                        if (i === 0) ctx.moveTo(X, Y)
                        else { ctx.lineTo(X, prev[1]); ctx.lineTo(X, Y) }
                    }
                }
                ctx.stroke()
            }

            // Столбцы от нуля (или от низа, если нуля в окне нет)
            function boxes(ctx, r, h) {
                let gap = Infinity
                for (let i = 1; i < r.length; i++) gap = Math.min(gap, Math.abs(r[i][0] - r[i - 1][0]))
                const bw = Math.max(1, root.fin(gap) ? gap * 0.8 : 12)
                const base = Math.max(0, Math.min(h, root.opts.ylog ? h : root.py(0)))
                const fill = ctx.fillStyle
                for (const [X, Y] of r) {
                    ctx.globalAlpha = 0.35
                    ctx.fillRect(X - bw / 2, Math.min(Y, base), bw, Math.abs(base - Y))
                    ctx.globalAlpha = 1
                    ctx.strokeRect(X - bw / 2, Math.min(Y, base), bw, Math.abs(base - Y))
                }
                ctx.fillStyle = fill
            }
        }

        // Подписи диапазона по y и названия осей
        Text {
            anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 4
            text: root.fmtY(root.view.y[1]) + (root.opts.ylabel ? "   " + root.opts.ylabel : "")
            font.family: Theme.font; font.pixelSize: 9; color: Theme.overlay1
        }
        Text {
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 4
            text: root.fmtY(root.view.y[0])
            font.family: Theme.font; font.pixelSize: 9; color: Theme.overlay1
        }
        Text {
            visible: root.opts.xlabel !== "" && root.opts.xlabel !== undefined
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 4
            text: root.opts.xlabel ?? ""
            font.family: Theme.font; font.pixelSize: 9; color: Theme.overlay1
        }

        // Курсор — HoverHandler, а не MouseArea: он не забирает наведение
        // у того, что под графиком (строка лончера с кликом и «лапкой»)
        HoverHandler {
            id: hover
        }

        // Что под курсором: [{si, x, y, th?, r?}]. Полярный — ближайшая точка;
        // функции — значение ровно под курсором (между соседними точками),
        // так у всех линий один x; данные — точка с ближайшим x
        readonly property var hits: {
            if (!hover.hovered || !root.plot || root.series.length === 0) return []
            const mx = hover.point.position.x, my = hover.point.position.y
            if (root.polar) {
                let best = null, bd = Infinity
                root.series.forEach((s, si) => {
                    for (let i = 0; i < s.xs.length; i++) {
                        if (!root.fin(s.ys[i])) continue
                        const d = Math.hypot(root.px(s.xs[i]) - mx, root.py(s.ys[i]) - my)
                        if (d < bd) { bd = d; best = { si: si, x: s.xs[i], y: s.ys[i], th: s.th[i], r: s.r[i] } }
                    }
                })
                return best ? [best] : []
            }
            const t = root.view.x[0] + mx / width * (root.view.x[1] - root.view.x[0])
            const x = root.opts.xlog ? Math.pow(10, t) : t
            const out = []
            root.series.forEach((s, si) => {
                if (s.fn) {
                    let i = 0
                    while (i < s.xs.length - 2 && s.xs[i + 1] < x) i++
                    const x0 = s.xs[i], x1 = s.xs[i + 1] ?? x0, y0 = s.ys[i], y1 = s.ys[i + 1] ?? y0
                    const k = x1 > x0 ? Math.max(0, Math.min(1, (x - x0) / (x1 - x0))) : 0
                    // Через асимптоту не тянем — берём ближнюю точку
                    const jump = Math.abs(root.py(y1) - root.py(y0)) > height * 1.5
                    const y = root.fin(y0) && root.fin(y1) && !jump ? y0 + (y1 - y0) * k
                            : k < 0.5 ? y0 : y1
                    out.push({ si: si, x: x, y: y })
                } else {
                    let bi = -1, bd = Infinity
                    for (let i = 0; i < s.xs.length; i++) {
                        const d = Math.abs(root.px(s.xs[i]) - mx)
                        if (d < bd) { bd = d; bi = i }
                    }
                    if (bi >= 0) out.push({ si: si, x: s.xs[bi], y: s.ys[bi] })
                }
            })
            return out
        }

        Repeater {
            model: area.hits
            Rectangle {
                required property var modelData
                readonly property real px: root.px(modelData.x)
                readonly property real py: root.py(modelData.y)
                visible: root.fin(modelData.y) && root.fin(px) && root.fin(py) && py >= 0 && py <= area.height
                x: px - width / 2
                y: py - height / 2
                width: 8; height: 8; radius: 4
                color: root.series.length > 1 ? root.seriesColor(root.colorIndex(modelData.si)) : Theme.text
                border.color: Theme.crust
                border.width: 1
            }
        }

        Text {
            visible: area.hits.length > 0
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 4
            textFormat: Text.StyledText
            text: {
                const h = area.hits
                if (h.length === 0) return ""
                if (root.polar)
                    return "θ = " + root.fmt(h[0].th) + "   r = " + root.fmt(h[0].r)
                const val = y => root.fin(y) ? root.fmt(y) : "—"
                if (h.length === 1)
                    return "x = " + root.fmt(h[0].x) + "   y = " + val(h[0].y)
                // Несколько линий: общий x один раз, значения — цветом линии
                const shared = h.every(e => e.x === h[0].x)
                return (shared ? "x = " + root.fmt(h[0].x) + "  " : "")
                    + h.map(e => "  <font color='" + root.seriesColor(root.colorIndex(e.si)) + "'>"
                        + (shared ? "" : root.fmt(e.x) + ": ") + val(e.y) + "</font>").join("")
            }
            font.family: Theme.font; font.pixelSize: 10; color: Theme.text
        }

        // Легенда в углу
        Rectangle {
            visible: root.legendAt !== "" && root.legendAt !== "below"
            x: root.legendAt.endsWith("left") ? 6 : parent.width - width - 6
            y: root.legendAt.startsWith("top") ? 18 : parent.height - height - 18
            width: legendCol.width + 12
            height: legendCol.height + 8
            radius: 6
            color: Theme.alpha(Theme.crust, 0.8)
            Column {
                id: legendCol
                x: 6; y: 4
                Repeater {
                    model: root.legendAt !== "below" ? root.series : []
                    LegendItem {}
                }
            }
        }
    }

    // Легенда полосой
    Flow {
        id: legendRow
        visible: root.legendAt === "below"
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 6
        spacing: 12
        Repeater {
            model: root.legendAt === "below" ? root.series : []
            LegendItem {}
        }
    }

    component LegendItem: Row {
        id: li
        required property var modelData
        required property int index
        readonly property int ci: root.colorIndex(index)
        spacing: 5
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: li.modelData.im ? 2 : 3; radius: 1.5
            opacity: li.modelData.im ? 0.7 : 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: li.ci === 0 && !root.opts.mono ? Theme.gradStart : root.seriesColor(li.ci) }
                GradientStop { position: 1; color: li.ci === 0 && !root.opts.mono ? Theme.gradEnd : root.seriesColor(li.ci) }
            }
        }
        Text {
            text: li.modelData.label
            width: Math.min(implicitWidth, 160)
            elide: Text.ElideRight
            font.family: Theme.font; font.pixelSize: 9; color: Theme.subtext0
        }
    }
}
