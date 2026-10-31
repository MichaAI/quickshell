import QtQuick
import "../config"

// QR-код в стиле шелла: подложка — градиент темы, модули — тёмные
// слитые в плавные фигуры, три «глазка» — скруглённые рамки. Полярность
// обычная (тёмное на светлом): светлый код на тёмном читают не все
// сканеры, zbar например — нет. matrix — строки
// из "0"/"1" (как их отдаёт qrencode -t ASCII), quiet — поля в модулях.
// save(путь) — та же картинка в файл (Canvas рисует в своё изображение).
Canvas {
    id: qr

    property var matrix: []
    property int quiet: 3
    property color fg: Theme.crust
    property color from: Theme.gradStart
    property color to: Theme.gradEnd

    renderTarget: Canvas.Image
    onMatrixChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function rr(ctx, x, y, w, h, r) {
        ctx.moveTo(x + r, y)
        ctx.arcTo(x + w, y, x + w, y + h, r)
        ctx.arcTo(x + w, y + h, x, y + h, r)
        ctx.arcTo(x, y + h, x, y, r)
        ctx.arcTo(x, y, x + w, y, r)
        ctx.closePath()
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const n = matrix.length
        if (n === 0) return
        const s = Math.min(width, height)
        const c = s / (n + quiet * 2)
        const o = quiet * c

        const g = ctx.createLinearGradient(0, 0, s, s)
        g.addColorStop(0, from)
        g.addColorStop(1, to)
        ctx.fillStyle = g
        ctx.beginPath()
        rr(ctx, 0, 0, s, s, c * 2.5)
        ctx.fill()

        ctx.fillStyle = fg

        // Глазки: рамка 7×7 и сердцевина 3×3
        const eyes = [[0, 0], [0, n - 7], [n - 7, 0]]
        const inEye = (r, k) => eyes.some(e => r >= e[0] && r < e[0] + 7 && k >= e[1] && k < e[1] + 7)
        ctx.beginPath()
        for (const e of eyes) {
            const x = o + e[1] * c, y = o + e[0] * c
            rr(ctx, x, y, 7 * c, 7 * c, 2.2 * c)
            rr(ctx, x + c, y + c, 5 * c, 5 * c, 1.4 * c)
            rr(ctx, x + 2 * c, y + 2 * c, 3 * c, 3 * c, 1 * c)
        }
        ctx.fillRule = Qt.OddEvenFill
        ctx.fill()

        // Модули сливаются в сплошные фигуры: каждый тёмный модуль —
        // квадрат, угол скругляется, только если по обе стороны от него
        // пусто (одиночный модуль — круг, ряд — капсула). Во внутренних
        // углах «Г» светлую клетку подрезает вогнутая скруглённая
        // перемычка, чтобы изгиб был плавным, а не ступенькой.
        const dark = (r, k) => r >= 0 && k >= 0 && r < n && k < n
            && matrix[r][k] === "1" && !inEye(r, k)
        const R = c * 0.5
        const fillets = []
        ctx.beginPath()
        ctx.fillRule = Qt.WindingFill
        for (let r = 0; r < n; r++) {
            for (let k = 0; k < n; k++) {
                const x = o + k * c, y = o + r * c
                if (dark(r, k)) {
                    const up = dark(r - 1, k), dn = dark(r + 1, k)
                    const lf = dark(r, k - 1), rt = dark(r, k + 1)
                    const tl = up || lf ? 0 : R, tr = up || rt ? 0 : R
                    const br = dn || rt ? 0 : R, bl = dn || lf ? 0 : R
                    ctx.moveTo(x + tl, y)
                    ctx.lineTo(x + c - tr, y)
                    if (tr) ctx.arcTo(x + c, y, x + c, y + tr, tr)
                    ctx.lineTo(x + c, y + c - br)
                    if (br) ctx.arcTo(x + c, y + c, x + c - br, y + c, br)
                    ctx.lineTo(x + bl, y + c)
                    if (bl) ctx.arcTo(x, y + c, x, y + c - bl, bl)
                    ctx.lineTo(x, y + tl)
                    if (tl) ctx.arcTo(x, y, x + tl, y, tl)
                    ctx.closePath()
                    continue
                }
                if (inEye(r, k)) continue
                for (const [dr, dk] of [[-1, -1], [-1, 1], [1, -1], [1, 1]])
                    if (dark(r + dr, k) && dark(r, k + dk) && dark(r + dr, k + dk))
                        fillets.push([x + (dk > 0 ? c : 0), y + (dr > 0 ? c : 0), -dk, -dr])
            }
        }
        ctx.fill()

        // Вогнутые перемычки — отдельной заливкой и с заходом e в тёмные
        // клетки: совпадающие рёбра в одном пути дают шов сглаживания.
        // (cx, cy) — угол, (sx, sy) — направление внутрь светлой клетки
        const f = R, e = c * 0.1
        ctx.beginPath()
        for (const [cx, cy, sx, sy] of fillets) {
            const pt = (u, v) => [cx + sx * u, cy + sy * v]
            ctx.moveTo(...pt(-e, -e))
            ctx.lineTo(...pt(f, -e))
            ctx.lineTo(...pt(f, 0))
            ctx.arcTo(...pt(0, 0), ...pt(0, f), f)
            ctx.lineTo(...pt(-e, f))
            ctx.closePath()
        }
        ctx.fill()
    }
}
