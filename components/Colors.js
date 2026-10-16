.pragma library

// Разбор и форматирование цветов. Внутри везде {r, g, b, a} в диапазоне 0..1.

function clamp(x, lo, hi) {
    return Math.max(lo, Math.min(hi, x))
}

function _num(s, max) {
    s = s.trim()
    if (s.endsWith("%"))
        return clamp(parseFloat(s) / 100, 0, 1)
    return clamp(parseFloat(s) / max, 0, 1)
}

// "#f80", "#ff8800", "#ff8800cc", "ff8800", "rgb(255 136 0)", "rgba(…)", "hsl(30 100% 50%)", "hsv(…)"
function parse(str) {
    const s = str.trim().toLowerCase()
    let m = s.match(/^#?([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/)
    if (m) {
        let h = m[1]
        if (h.length <= 4)
            h = h.split("").map(c => c + c).join("")
        const n = i => parseInt(h.substr(i, 2), 16) / 255
        return { r: n(0), g: n(2), b: n(4), a: h.length === 8 ? n(6) : 1 }
    }
    m = s.match(/^(rgba?|hsla?|hsva?|hsb)\(\s*([^)]*)\)$/)
    if (!m)
        return null
    const parts = m[2].split(/[\s,\/]+/).filter(x => x !== "")
    if (parts.length < 3 || parts.length > 4 || parts.some(p => isNaN(parseFloat(p))))
        return null
    const a = parts.length === 4 ? _num(parts[3], parts[3].includes("%") ? 100 : 1) : 1
    if (m[1].startsWith("rgb"))
        return { r: _num(parts[0], 255), g: _num(parts[1], 255), b: _num(parts[2], 255), a: a }
    const h = ((parseFloat(parts[0]) % 360) + 360) % 360 / 360
    const x = _num(parts[1], 100), y = _num(parts[2], 100)
    const c = m[1].startsWith("hsl") ? fromHsl(h, x, y) : fromHsv(h, x, y)
    c.a = a
    return c
}

function fromHsv(h, s, v) {
    const i = Math.floor(h * 6) % 6
    const f = h * 6 - Math.floor(h * 6)
    const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    const rgb = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i]
    return { r: rgb[0], g: rgb[1], b: rgb[2], a: 1 }
}

function fromHsl(h, s, l) {
    const v = l + s * Math.min(l, 1 - l)
    const sv = v === 0 ? 0 : 2 * (1 - l / v)
    return fromHsv(h, sv, v)
}

function toHsv(c) {
    const max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b)
    const d = max - min
    let h = 0
    if (d > 0) {
        if (max === c.r) h = ((c.g - c.b) / d + 6) % 6
        else if (max === c.g) h = (c.b - c.r) / d + 2
        else h = (c.r - c.g) / d + 4
        h /= 6
    }
    return { h: h, s: max === 0 ? 0 : d / max, v: max }
}

function toHsl(c) {
    const hsv = toHsv(c)
    const l = hsv.v * (1 - hsv.s / 2)
    const s = l === 0 || l === 1 ? 0 : (hsv.v - l) / Math.min(l, 1 - l)
    return { h: hsv.h, s: s, l: l }
}

function _hex2(x) {
    return Math.round(clamp(x, 0, 1) * 255).toString(16).padStart(2, "0")
}

function hex(c) {
    return "#" + _hex2(c.r) + _hex2(c.g) + _hex2(c.b) + (c.a < 1 ? _hex2(c.a) : "")
}

function _p(x) {
    return Math.round(x * 100)
}

function _alpha(c) {
    return c.a < 1 ? " / " + (Math.round(c.a * 100) / 100) : ""
}

function rgb(c) {
    const n = x => Math.round(clamp(x, 0, 1) * 255)
    return "rgb(" + n(c.r) + " " + n(c.g) + " " + n(c.b) + _alpha(c) + ")"
}

function hsl(c) {
    const x = toHsl(c)
    return "hsl(" + Math.round(x.h * 360) + " " + _p(x.s) + "% " + _p(x.l) + "%" + _alpha(c) + ")"
}

function hsv(c) {
    const x = toHsv(c)
    return "hsv(" + Math.round(x.h * 360) + " " + _p(x.s) + "% " + _p(x.v) + "%" + _alpha(c) + ")"
}

// Все форматы для копирования: [[подпись, строка]]
function formats(c) {
    return [["HEX", hex(c)], ["RGB", rgb(c)], ["HSL", hsl(c)], ["HSV", hsv(c)]]
}

// Читаемый цвет текста поверх c
function onColor(c) {
    const lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    return lum > 0.55 ? "#11111b" : "#cdd6f4"
}

// ===== OkLab / OkLCh =====

function _lin(x) {
    return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
}

function _srgb(x) {
    x = clamp(x, 0, 1)
    return x <= 0.0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - 0.055
}

// sRGB 0..1 → [L, a, b]
function oklab(r, g, b) {
    r = _lin(r); g = _lin(g); b = _lin(b)
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
}

// [L, a, b] → линейный sRGB (может выйти за 0..1)
function _okToLinear(L, A, B) {
    const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
    const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
    const s = Math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
}

// OkLCh → {r, g, b, a}; хрома сбавляется, пока цвет не влезет в sRGB
function fromOklch(L, C, h) {
    let rgb = _okToLinear(L, C * Math.cos(h), C * Math.sin(h))
    while (C > 0 && rgb.some(x => x < -1e-4 || x > 1 + 1e-4)) {
        C = Math.max(0, C - 0.005)
        rgb = _okToLinear(L, C * Math.cos(h), C * Math.sin(h))
    }
    return { r: _srgb(rgb[0]), g: _srgb(rgb[1]), b: _srgb(rgb[2]), a: 1 }
}

// Дальтонизм: линейный sRGB глазами протанопа и дейтеранопа (Machado 2009)
const _cvd = [
    [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
]

function _labOf(c) {
    return oklab(c.r, c.g, c.b)
}

// Насколько пара различима для красно-зелёного дальтоника: меньшее ΔE OkLab
// из протанопии и дейтеранопии
function cvdDistance(c1, c2) {
    const lin = c => [_lin(c.r), _lin(c.g), _lin(c.b)]
    let best = Infinity
    for (const M of _cvd) {
        const sim = c => {
            const v = lin(c)
            const o = M.map(row => _srgb(row[0] * v[0] + row[1] * v[1] + row[2] * v[2]))
            return oklab(o[0], o[1], o[2])
        }
        const p = sim(c1), q = sim(c2)
        best = Math.min(best, Math.hypot(p[0] - q[0], p[1] - q[1], p[2] - q[2]))
    }
    return best
}

// Два акцента из картинки (RGBA-байты квадрата, например getImageData().data)
// для градиента на тёмном фоне. null — картинка почти серая.
//
// 1. Пиксели — в OkLab; центр кадра весит больше краёв (там обычно сюжет,
//    по краям — фон и рамки).
// 2. k-means на 8 цветов (детерминированно: старт — самые далёкие друг от
//    друга точки, так что одна обложка — всегда одни цвета).
// 3. Очки цвета: доля площади в степени 0.6 (маленькое яркое пятно может
//    перебить большой тусклый фон) × насыщенность; почти серые, почти чёрные
//    и почти белые не участвуют.
// 4. Второй — лучший по очкам из тех, что отличаются оттенком хотя бы на
//    25°, со штрафом за почти противоположные: градиент между ними в OkLab
//    идёт через серое. И с наградой за различимость при красно-зелёном
//    дальтонизме — иначе градиент для такого глаза плоский.
//    Нет второго — сосед по кругу оттенков, тот, что различимее.
//    Если пара всё равно сливается для дальтоника (красный с зелёным),
//    разводим её по яркости: оттенки обложки остаются, а градиент виден.
// 5. Яркость — около L, чтобы читалось; насыщенность — своя у обложки,
//    но не больше C: блёклая обложка даёт спокойные акценты, а не кислоту.
function accents(px, L, C) {
    const n = px.length / 4, side = Math.round(Math.sqrt(n)) || 1
    const pts = [], wts = []
    for (let i = 0; i < n; i++) {
        const a = px[4 * i + 3] / 255
        if (a < 0.5)
            continue
        const x = (i % side + 0.5) / side - 0.5, y = (Math.floor(i / side) + 0.5) / side - 0.5
        pts.push(oklab(px[4 * i] / 255, px[4 * i + 1] / 255, px[4 * i + 2] / 255))
        wts.push(a * (1 - 0.6 * Math.min(1, (x * x + y * y) * 2)))
    }
    if (pts.length === 0)
        return null
    const d2 = (p, q) => (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2

    // k-means
    const K = Math.min(8, pts.length)
    let mean = [0, 0, 0], W = 0
    pts.forEach((p, i) => { for (let k = 0; k < 3; k++) mean[k] += p[k] * wts[i]; W += wts[i] })
    mean = mean.map(v => v / W)
    const cent = []
    let near = pts.map(p => d2(p, mean))
    for (let k = 0; k < K; k++) {
        let far = 0
        for (let i = 1; i < pts.length; i++) if (near[i] * wts[i] > near[far] * wts[far]) far = i
        cent.push(pts[far].slice())
        near = near.map((v, i) => Math.min(v, d2(pts[i], pts[far])))
    }
    let own = new Array(pts.length).fill(0)
    for (let it = 0; it < 10; it++) {
        own = pts.map(p => { let b = 0; for (let k = 1; k < K; k++) if (d2(p, cent[k]) < d2(p, cent[b])) b = k; return b })
        const sum = cent.map(() => [0, 0, 0, 0])
        pts.forEach((p, i) => { const s = sum[own[i]]; s[0] += p[0] * wts[i]; s[1] += p[1] * wts[i]; s[2] += p[2] * wts[i]; s[3] += wts[i] })
        sum.forEach((s, k) => { if (s[3] > 0) cent[k] = [s[0] / s[3], s[1] / s[3], s[2] / s[3]] })
    }
    const share = cent.map(() => 0)
    own.forEach((k, i) => share[k] += wts[i] / W)

    const sat = (x, lo, hi) => clamp((x - lo) / (hi - lo), 0, 1)
    const cl = cent.map((c, k) => {
        const ch = Math.hypot(c[1], c[2])
        return {
            L: c[0], C: ch, h: Math.atan2(c[2], c[1]), share: share[k],
            score: share[k] < 0.02 ? 0
                 : Math.pow(share[k], 0.6) * sat(ch, 0.03, 0.09) * (0.5 + ch * 4)
                   * sat(c[0], 0.15, 0.3) * (1 - sat(c[0], 0.9, 0.98))
        }
    }).filter(c => c.score > 0).sort((p, q) => q.score - p.score)
    if (cl.length === 0)
        return null

    const make = (c, dL) => fromOklch(clamp(L + (c.L - 0.6) * 0.15, L - 0.05, L + 0.05) + (dL ?? 0),
                                      clamp(c.C * 1.25, 0.06, C), c.h)
    const hueGap = (a, b) => { const d = Math.abs(a - b) % (2 * Math.PI); return Math.min(d, 2 * Math.PI - d) * 180 / Math.PI }
    const first = cl[0], c1 = make(first)
    const pairScore = c2 => sat(cvdDistance(c1, c2), 0.02, 0.08) * 0.7 + 0.3

    let second = null, best = 0
    for (const c of cl.slice(1)) {
        const gap = hueGap(c.h, first.h)
        if (gap < 25)
            continue
        const s = c.score * (gap > 120 ? 1 - 0.6 * (gap - 120) / 60 : 1) * pairScore(make(c))
        if (s > best && c.score > first.score * 0.12) { best = s; second = c }
    }
    if (!second) {
        // Соседний оттенок: в ту сторону и на столько, где различимее
        let bs = -1
        for (const dh of [40, -40, 60, -60]) {
            const c = { L: first.L, C: first.C, h: first.h + dh * Math.PI / 180 }
            const s = cvdDistance(c1, make(c))
            if (s > bs) { bs = s; second = c }
        }
    }
    let c2 = make(second)
    if (cvdDistance(c1, c2) < 0.05) {
        // Светлее тот, что светлее на обложке
        const up = first.L >= second.L ? 1 : -1
        return [make(first, 0.04 * up), make(second, -0.06 * up)]
    }
    return [c1, c2]
}
