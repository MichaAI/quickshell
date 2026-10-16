.pragma library

// Формы MD3 Expressive (MaterialShapes) и морф между ними — для MaterialShape.
//
// Форма — скруглённый многоугольник или звезда, как RoundedPolygon в
// androidx.graphics.shapes: вершины на единичной окружности (у звезды —
// через одну на внутреннем радиусе), каждый угол скруглён дугой радиуса
// rounding (в долях радиуса формы). Овал и пилюля — суперэллипсы.
// Все формы звёздные относительно центра, поэтому хранятся как радиус от
// угла: таблица на N_TABLE углов плюс углы выпуклых вершин — «особенности».
//
// Морф, как Morph из androidx: выпуклые углы одной формы находят пары
// среди углов другой (по порядку обхода, с подбором сдвига, лишние —
// без пары), и по этим парам строится соответствие углов обхода. Угол
// перетекает в свой угол, лишний — сливается с соседями, а не гаснет.

const N_TABLE = 720
const TAU = 2 * Math.PI

function _norm(a) {
    return ((a % TAU) + TAU) % TAU
}

// Точки контура → таблица радиуса по углу. Контур звёздный: угол точек
// растёт монотонно, так что хватает линейной интерполяции между соседями
function _table(pts) {
    const pol = pts.map(([x, y]) => [_norm(Math.atan2(y, x)), Math.hypot(x, y)]).sort((a, b) => a[0] - b[0])
    const out = new Float64Array(N_TABLE)
    let j = 0
    for (let i = 0; i < N_TABLE; i++) {
        const a = i / N_TABLE * TAU
        while (j < pol.length && pol[j][0] < a) j++
        const p = pol[(j - 1 + pol.length) % pol.length], q = pol[j % pol.length]
        let a0 = p[0], a1 = q[0]
        if (j === 0) a0 -= TAU
        if (j >= pol.length) a1 += TAU
        const t = a1 > a0 ? (a - a0) / (a1 - a0) : 0
        out[i] = p[1] + (q[1] - p[1]) * t
    }
    // Самая дальняя точка — на радиусе 1
    let max = 0
    for (let i = 0; i < N_TABLE; i++) max = Math.max(max, out[i])
    for (let i = 0; i < N_TABLE; i++) out[i] /= max
    return out
}

// Скруглённый многоугольник по вершинам; rounding — радиус скругления
// каждого угла
function _rounded(verts, rounding) {
    const n = verts.length, pts = []
    for (let i = 0; i < n; i++) {
        const p = verts[(i - 1 + n) % n], v = verts[i], q = verts[(i + 1) % n]
        const d1 = [p[0] - v[0], p[1] - v[1]], d2 = [q[0] - v[0], q[1] - v[1]]
        const l1 = Math.hypot(...d1), l2 = Math.hypot(...d2)
        const u1 = [d1[0] / l1, d1[1] / l1], u2 = [d2[0] / l2, d2[1] / l2]
        const cos = Math.max(-1, Math.min(1, u1[0] * u2[0] + u1[1] * u2[1]))
        const half = Math.acos(cos) / 2
        // Касательные не длиннее половины ребра
        let r = rounding[i]
        let tl = r / Math.tan(half)
        const maxT = Math.min(l1, l2) / 2
        if (tl > maxT) { tl = maxT; r = tl * Math.tan(half) }
        const a = [v[0] + u1[0] * tl, v[1] + u1[1] * tl], b = [v[0] + u2[0] * tl, v[1] + u2[1] * tl]
        // Центр дуги — по биссектрисе
        const bis = [u1[0] + u2[0], u1[1] + u2[1]], bl = Math.hypot(...bis) || 1
        const cd = r / Math.sin(half)
        const c = [v[0] + bis[0] / bl * cd, v[1] + bis[1] / bl * cd]
        let s = Math.atan2(a[1] - c[1], a[0] - c[0]), e = Math.atan2(b[1] - c[1], b[0] - c[0])
        // Короткая дуга от a к b
        let sweep = e - s
        while (sweep > Math.PI) sweep -= TAU
        while (sweep < -Math.PI) sweep += TAU
        const steps = 24
        for (let k = 0; k <= steps; k++) {
            const t = s + sweep * k / steps
            pts.push([c[0] + r * Math.cos(t), c[1] + r * Math.sin(t)])
        }
    }
    // Рёбра — прямые между дугами: добиваем точками, чтобы таблица не
    // провисала на длинных сторонах
    const dense = []
    for (let i = 0; i < pts.length; i++) {
        const a = pts[i], b = pts[(i + 1) % pts.length]
        const l = Math.hypot(b[0] - a[0], b[1] - a[1]), k = Math.max(1, Math.ceil(l / 0.01))
        for (let j = 0; j < k; j++)
            dense.push([a[0] + (b[0] - a[0]) * j / k, a[1] + (b[1] - a[1]) * j / k])
    }
    return dense
}

// Звезда: n лучей, внутренний радиус inner (1 — многоугольник), скругление.
// Первый луч смотрит вверх
function star(n, inner, rounding, innerRounding) {
    const verts = [], features = []
    const m = inner < 1 ? 2 * n : n
    for (let i = 0; i < m; i++) {
        const a = -Math.PI / 2 + i / m * TAU
        const r = inner < 1 && i % 2 === 1 ? inner : 1
        verts.push([r * Math.cos(a), r * Math.sin(a)])
        if (r === 1)
            features.push(_norm(a))
    }
    const ir = innerRounding ?? rounding
    const pts = _rounded(verts, verts.map((v, i) => inner < 1 && i % 2 === 1 ? ir : rounding))
    return { table: _table(pts), features: features }
}

// Суперэллипс со степенью p, вытянутый по x в aspect раз (меньше 1 — по y)
function superellipse(p, aspect) {
    const pts = []
    for (let i = 0; i < N_TABLE; i++) {
        const a = i / N_TABLE * TAU
        const c = Math.cos(a), s = Math.sin(a)
        const x = Math.sign(c) * Math.pow(Math.abs(c), 2 / p) * aspect
        const y = Math.sign(s) * Math.pow(Math.abs(s), 2 / p)
        pts.push([x, y])
    }
    return { table: _table(pts), features: [] }
}

// ===== Формы =====
const circle = superellipse(2, 1)
const oval = superellipse(2, 1.3)
const pill = superellipse(3.5, 1.45)
// Капля — овал стоймя
const drop = superellipse(2, 0.8)
const pentagon = star(5, 1, 0.172)
const cookie4 = star(4, 0.8, 0.3, 0.2)
const cookie9 = star(9, 0.8, 0.5, 0.3)
const softBurst = star(10, 0.8, 0.15, 0.25)
const sunny = star(8, 0.8, 0.15)
const verySunny = star(8, 0.65, 0.3)

// Цикл M3E LoadingIndicator
const loading = [softBurst, cookie9, pentagon, pill, sunny, cookie4, oval]

// ===== Морф =====

function radiusAt(shape, a) {
    const f = _norm(a) / TAU * N_TABLE
    const i = Math.floor(f) % N_TABLE, t = f - Math.floor(f)
    return shape.table[i] * (1 - t) + shape.table[(i + 1) % N_TABLE] * t
}

function _angDist(a, b) {
    const d = Math.abs(_norm(a) - _norm(b))
    return Math.min(d, TAU - d)
}

// Пары углов A ↔ B по порядку обхода: сдвиг по кругу перебором, внутри —
// выравнивание динамикой, угол без пары стоит штраф
function _pairs(fa, fb) {
    if (fa.length === 0 || fb.length === 0)
        return []
    const n = fa.length, m = fb.length
    const skip = Math.PI / Math.max(n, m)
    let best = null, bestCost = Infinity
    for (let s = 0; s < m; s++) {
        const B = []
        for (let j = 0; j < m; j++) B.push(fb[(s + j) % m])
        // D[i][j] — лучшая цена для первых i углов A и j углов B
        const D = [], P = []
        for (let i = 0; i <= n; i++) { D.push(new Array(m + 1).fill(Infinity)); P.push(new Array(m + 1).fill(0)) }
        D[0][0] = 0
        for (let i = 0; i <= n; i++)
            for (let j = 0; j <= m; j++) {
                const d = D[i][j]
                if (d === Infinity) continue
                if (i < n && j < m) {
                    const c = d + _angDist(fa[i], B[j])
                    if (c < D[i + 1][j + 1]) { D[i + 1][j + 1] = c; P[i + 1][j + 1] = 0 }
                }
                if (i < n && d + skip < D[i + 1][j]) { D[i + 1][j] = d + skip; P[i + 1][j] = 1 }
                if (j < m && d + skip < D[i][j + 1]) { D[i][j + 1] = d + skip; P[i][j + 1] = 2 }
            }
        if (D[n][m] < bestCost) {
            bestCost = D[n][m]
            const pairs = []
            let i = n, j = m
            while (i > 0 || j > 0) {
                const k = P[i][j]
                if (k === 0) { pairs.push([fa[i - 1], B[j - 1]]); i--; j-- }
                else if (k === 1) i--
                else j--
            }
            best = pairs.reverse()
        }
    }
    return best
}

const _plans = new Map()

// Соответствие углов обхода A → B на n точек: для каждого угла A (равный
// шаг) — угол B. Между парами углов — линейно по кругу
function plan(a, b, n) {
    const key = a.table.length + ":" + n + ":" + _id(a) + ">" + _id(b)
    if (_plans.has(key))
        return _plans.get(key)
    const pairs = _pairs(a.features, b.features)
    const out = new Float64Array(n)
    if (pairs.length === 0) {
        for (let k = 0; k < n; k++) out[k] = k / n * TAU
    } else {
        // Якоря: угол A → угол B, B «размотан», чтобы шёл не убывая
        const anchors = pairs.map(([x, y]) => [_norm(x), _norm(y)]).sort((p, q) => p[0] - q[0])
        for (let i = 1; i < anchors.length; i++)
            while (anchors[i][1] < anchors[i - 1][1]) anchors[i][1] += TAU
        // Один якорь — просто поворот
        for (let k = 0; k < n; k++) {
            const x = k / n * TAU
            let i = anchors.findIndex(p => p[0] > x)
            let p, q
            if (i === -1) { p = anchors[anchors.length - 1]; q = [anchors[0][0] + TAU, anchors[0][1] + TAU] }
            else if (i === 0) { p = [anchors[anchors.length - 1][0] - TAU, anchors[anchors.length - 1][1] - TAU]; q = anchors[0] }
            else { p = anchors[i - 1]; q = anchors[i] }
            const t = q[0] > p[0] ? (x - p[0]) / (q[0] - p[0]) : 0
            out[k] = p[1] + (q[1] - p[1]) * t
        }
    }
    _plans.set(key, out)
    return out
}

let _ids = new Map(), _next = 0
function _id(shape) {
    if (!_ids.has(shape))
        _ids.set(shape, _next++)
    return _ids.get(shape)
}

// Точки контура в морфе: [x0, y0, x1, y1, …] в долях радиуса, повёрнутые
// на turn оборотов; t — 0 у A, 1 у B (может выходить за край у пружины)
function points(a, b, t, turn, n) {
    const pl = plan(a, b, n), rot = turn * TAU
    const out = new Array(2 * n)
    for (let k = 0; k < n; k++) {
        const aa = k / n * TAU, ab = pl[k]
        const ra = radiusAt(a, aa), rb = radiusAt(b, ab)
        const xa = ra * Math.cos(aa), ya = ra * Math.sin(aa)
        const xb = rb * Math.cos(ab), yb = rb * Math.sin(ab)
        const x = xa + (xb - xa) * t, y = ya + (yb - ya) * t
        out[2 * k] = x * Math.cos(rot) - y * Math.sin(rot)
        out[2 * k + 1] = x * Math.sin(rot) + y * Math.cos(rot)
    }
    return out
}
