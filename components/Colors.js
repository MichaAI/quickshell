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
