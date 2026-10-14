import QtQuick
import "../config"

// График функции по готовым точкам {xs, ys, min, max}: оси, сетка,
// градиентная линия и значение под курсором.
Item {
    id: root

    property var plot: null

    readonly property var ys: plot ? plot.ys : []
    // Диапазон по y — без выбросов (tan(x) у асимптот), с полями
    readonly property var range: {
        const v = ys.filter(y => isFinite(y)).slice().sort((a, b) => a - b)
        if (v.length === 0) return [-1, 1]
        let lo = v[Math.floor(v.length * 0.02)], hi = v[Math.ceil(v.length * 0.98) - 1]
        if (hi - lo < 1e-9) { lo -= 1; hi += 1 }
        const pad = (hi - lo) * 0.08
        return [lo - pad, hi + pad]
    }

    function px(x) { return (x - plot.min) / (plot.max - plot.min) * width }
    function py(y) { return height - (y - range[0]) / (range[1] - range[0]) * height }

    function fmt(v) {
        const a = Math.abs(v)
        if (a !== 0 && (a >= 1e5 || a < 1e-3)) return v.toExponential(2)
        return String(Math.round(v * 1000) / 1000)
    }

    onPlotChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.alpha(Theme.crust, 0.6)
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!root.plot || width <= 0) return
            const w = width, h = height

            // Сетка
            ctx.strokeStyle = Theme.alpha(Theme.surface1, 0.5)
            ctx.lineWidth = 1
            for (let i = 1; i < 8; i++) {
                ctx.beginPath(); ctx.moveTo(w * i / 8, 0); ctx.lineTo(w * i / 8, h); ctx.stroke()
            }
            for (let i = 1; i < 4; i++) {
                ctx.beginPath(); ctx.moveTo(0, h * i / 4); ctx.lineTo(w, h * i / 4); ctx.stroke()
            }

            // Оси, если попадают в окно
            ctx.strokeStyle = Theme.overlay0
            const x0 = root.px(0), y0 = root.py(0)
            if (x0 >= 0 && x0 <= w) { ctx.beginPath(); ctx.moveTo(x0, 0); ctx.lineTo(x0, h); ctx.stroke() }
            if (y0 >= 0 && y0 <= h) { ctx.beginPath(); ctx.moveTo(0, y0); ctx.lineTo(w, y0); ctx.stroke() }

            // Кривая; разрываем на NaN и на скачках через всю высоту (асимптоты)
            const grad = ctx.createLinearGradient(0, 0, w, 0)
            grad.addColorStop(0, Theme.gradStart)
            grad.addColorStop(1, Theme.gradEnd)
            ctx.strokeStyle = grad
            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.beginPath()
            let pen = false, prev = 0
            for (let i = 0; i < root.ys.length; i++) {
                const y = root.ys[i]
                if (!isFinite(y)) { pen = false; continue }
                const X = root.px(root.plot.xs[i]), Y = root.py(y)
                if (pen && Math.abs(Y - prev) > h * 1.5) pen = false
                if (pen) ctx.lineTo(X, Y)
                else ctx.moveTo(X, Y)
                pen = true
                prev = Y
            }
            ctx.stroke()
        }
    }

    // Подписи диапазонов
    Text {
        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 4
        text: root.fmt(root.range[1])
        font.family: Theme.font; font.pixelSize: 9; color: Theme.overlay1
    }
    Text {
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 4
        text: root.fmt(root.range[0])
        font.family: Theme.font; font.pixelSize: 9; color: Theme.overlay1
    }

    // Значение под курсором
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    readonly property int hoverIdx: hover.containsMouse && ys.length > 1
        ? Math.max(0, Math.min(ys.length - 1, Math.round(hover.mouseX / width * (ys.length - 1)))) : -1

    Rectangle {
        visible: root.hoverIdx >= 0 && isFinite(root.ys[root.hoverIdx] ?? NaN)
        x: root.hoverIdx >= 0 ? root.px(root.plot.xs[root.hoverIdx]) - width / 2 : 0
        y: visible ? root.py(root.ys[root.hoverIdx]) - height / 2 : 0
        width: 8; height: 8; radius: 4
        color: Theme.text
    }

    Text {
        visible: root.hoverIdx >= 0
        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 4
        text: root.hoverIdx < 0 ? "" : "x = " + root.fmt(root.plot.xs[root.hoverIdx])
            + "   y = " + (isFinite(root.ys[root.hoverIdx]) ? root.fmt(root.ys[root.hoverIdx]) : "—")
        font.family: Theme.font; font.pixelSize: 10; color: Theme.text
    }
}
