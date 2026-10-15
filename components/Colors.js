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

// Два акцента из картинки (RGBA-байты, например getImageData().data):
// оттенки — два пика гистограммы, где голос пикселя — его насыщенность;
// яркость L и насыщенность C — свои, как у темы, чтобы читалось на тёмном.
// null — картинка почти серая.
function accents(px, L, C) {
    const bins = 36, hist = new Array(bins).fill(0)
    for (let i = 0; i + 3 < px.length; i += 4) {
        const lab = oklab(px[i] / 255, px[i + 1] / 255, px[i + 2] / 255)
        const c = Math.hypot(lab[1], lab[2])
        const w = Math.max(0, c - 0.03) * (1 - Math.abs(lab[0] - 0.6)) * px[i + 3] / 255
        const h = (Math.atan2(lab[2], lab[1]) + 2 * Math.PI) % (2 * Math.PI)
        hist[Math.floor(h / (2 * Math.PI) * bins) % bins] += w
    }
    const sm = hist.map((v, i) => hist[(i + bins - 1) % bins] * 0.25 + v * 0.5 + hist[(i + 1) % bins] * 0.25)
    if (sm.reduce((a, b) => a + b, 0) < 1e-3)
        return null
    const dist = (a, b) => { const d = Math.abs(a - b) % bins; return Math.min(d, bins - d) }
    let i1 = 0
    for (let i = 1; i < bins; i++) if (sm[i] > sm[i1]) i1 = i
    let i2 = -1
    for (let i = 0; i < bins; i++)
        if (dist(i, i1) >= 4 && (i2 < 0 || sm[i] > sm[i2])) i2 = i
    // Второго цвета нет — берём соседний оттенок
    if (i2 < 0 || sm[i2] < 0.15 * sm[i1])
        i2 = (i1 + 5) % bins
    const hue = i => (i + 0.5) / bins * 2 * Math.PI
    return [fromOklch(L, C, hue(i1)), fromOklch(L, C, hue(i2))]
}
