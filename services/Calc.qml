pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Калькулятор лончера: один живой процесс qalc, общение через stdin/stdout.
// Каждый запрос — выражение и следом строка-маркер "@@<id>": всё, что qalc
// напечатал между ними, и есть ответ. Переменные и ans храним сами.
Singleton {
    id: root

    readonly property string varsFile: Quickshell.env("HOME") + "/.cache/quickshell-launcher-vars"

    property var vars: ({})          // имя -> значение (строкой, как вернул qalc)
    property string ans: ""
    property bool ready: false

    property int _seq: 0
    property var _pending: ({})      // id -> callback
    property var _lines: []

    // Первые слова, которые qalc считает командами (quit, set, save…) — не считаем
    readonly property var _commands: [
        "quit", "exit", "set", "save", "store", "delete", "assume", "base", "mode",
        "help", "info", "list", "find", "function", "variable", "keep", "unkeep",
        "exrates", "stack", "swap", "rotate", "copy", "clear", "pop", "rpn",
        "approximate", "exact", "factor", "simplify", "expand", "partial", "MC",
        "MS", "MR", "MRC", "M+", "M-", "history"
    ]

    // Цели "to …", которые не единицы — их не трогаем
    readonly property var _formats: [
        "hex", "bin", "oct", "dec", "decimal", "decimals", "roman", "time", "fraction",
        "fractions", "base", "bases", "bijective", "factors", "partial", "utc", "calendars",
        "prefix", "optimal", "si", "binary", "duo", "sexa", "unicode", "mixed", "bcd", "fp32",
        "fp64", "fp16", "polar", "cis", "rectangular", "exp", "sci", "eng"
    ]

    // Для автодополнения: самое ходовое из функций, констант и единиц
    readonly property var builtins: [
        "sqrt(", "cbrt(", "root(", "abs(", "round(", "floor(", "ceil(", "trunc(",
        "sin(", "cos(", "tan(", "asin(", "acos(", "atan(", "sinh(", "cosh(", "tanh(",
        "ln(", "log(", "log2(", "log10(", "exp(", "factorial(", "gcd(", "lcm(",
        "mod(", "rem(", "max(", "min(", "sum(", "mean(", "median(", "random(",
        "deg(", "rad(", "hex(", "bin(", "oct(", "solve(", "diff(", "integrate(",
        "pi", "e", "golden", "c", "today", "now", "tomorrow", "yesterday",
        "to", "hex", "bin", "oct", "roman", "time", "kilometer", "meter", "mile",
        "inch", "foot", "yard", "celsius", "fahrenheit", "kelvin", "kilogram",
        "gram", "pound", "ounce", "liter", "gallon", "byte", "kilobyte", "megabyte",
        "gigabyte", "terabyte", "kibibyte", "mebibyte", "gibibyte", "second",
        "minute", "hour", "day", "week", "month", "year", "USD", "EUR", "RUB",
        "GBP", "CNY", "JPY", "BTC", "percent"
    ]

    readonly property var names: [...Object.keys(vars), "ans", ...builtins]

    // Похоже ли на выражение (для подмешивания в обычный поиск)
    function looksLikeMath(s) {
        const t = s.trim()
        if (/^plot\s*\(/i.test(t)) return true
        if (t === "" || !/\d/.test(t)) return false
        if (/^\d+$/.test(t)) return false
        // Начинается как выражение: число, скобка, функция или переменная с оператором
        const v = t.match(/^([a-zA-Z_]\w*)\s*[-+*/^%]/)
        const head = /^[\d(.\-+]/.test(t) || /^[a-zA-Z_]\w*\(/.test(t)
            || (v && (v[1] === "ans" || vars[v[1]] !== undefined)) || parseAssign(t) !== null
        return head && /[-+*/^%()=]|\s(to|in|as)\s|^0[xbo]/i.test(t)
    }

    // "x = 2+2" / "x := 2+2" → {name, expr}
    function parseAssign(s) {
        const m = s.trim().match(/^([a-zA-Z_][a-zA-Z0-9_]*)\s*:?=\s*(.+)$/)
        if (!m || m[1] === "ans" || m[2].startsWith("=")) return null
        return { name: m[1], expr: m[2] }
    }

    // "0,5 + 1" → "0.5 + 1": запятая между цифрами вне скобок — десятичная
    // (внутри скобок функции это разделитель аргументов: max(1,2))
    function _decimalComma(e) {
        let depth = 0, out = ""
        for (let i = 0; i < e.length; i++) {
            const c = e[i]
            if (c === "(" || c === "[") depth++
            else if (c === ")" || c === "]") depth--
            out += c === "," && depth === 0 && /\d/.test(e[i - 1] ?? "") && /\d/.test(e[i + 1] ?? "")
                ? "." : c
        }
        return out
    }

    // Функции с побочными эффектами: command() запускает программы, export()
    // пишет файлы, plot() открывает gnuplot. Превью считается на каждую букву —
    // их не трогаем вообще (график рисует сам лончер, см. plot())
    function hasSideEffects(e) {
        return /\b(command|export|load|plot|save)\s*\(/i.test(e)
    }

    function _prepare(expr) {
        let e = expr.replace(/[\r\n]+/g, " ").trim()
        // "15% of 200" — qalc его не понимает
        e = e.replace(/(\d+(?:\.\d+)?)\s*%\s*(?:of|от)\s+/gi, "($1/100) * ")
        e = _decimalComma(e)
        e = e.replace(/\bans\b/g, "(" + (ans !== "" ? ans : "0") + ")")
        // "to mi" → "to -mi": без смешанных единиц (6 mi + 376 yd + …)
        e = e.replace(/(\s(?:to|in|as)\s+)([a-zA-Z]+)\s*$/, (m, pre, unit) =>
            _formats.includes(unit.toLowerCase()) ? m : pre + "-" + unit)
        return e
    }

    // Посчитать: callback(result) — строка или "" при ошибке. Возвращает id.
    // exact — точный ответ: дроби и корни вместо десятичных (2 × √(2), 7/12)
    function evaluate(expr, callback, exact) {
        const e = _prepare(expr)
        const first = e.split(/[\s(]/)[0]
        if (e === "" || _commands.includes(first) || e.startsWith('"') || hasSideEffects(e)) {
            callback("")
            return -1
        }
        if (!proc.running) {
            callback("")
            return -1
        }
        const id = ++_seq
        _pending[id] = callback
        // Пустая строка после выражения — «жертва»: долгое вычисление qalc
        // прерывает по любой введённой строке и съедает её. Пусть съест пустую,
        // а не маркер. Если вычисление быстрое, пустая строка ничего не делает.
        if (exact)
            proc.write("set approx exact\nset fr 2\n" + e + '\n\n"@@' + id + '"\n'
                + "set approx approximate\nset fr 0\n")
        else
            proc.write(e + '\n\n"@@' + id + '"\n')
        return id
    }

    // Ответ qalc в виде, который поймут другие программы: 2 × √(2) → 2*sqrt(2)
    function plain(s) {
        const sup = { "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5",
                      "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-" }
        return s
            .replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹⁻]+/g, m => "^" + m.split("").map(c => sup[c]).join(""))
            .replace(/√/g, "sqrt").replace(/∛/g, "cbrt").replace(/π/g, "pi")
            .replace(/\s*[×⋅·]\s*/g, "*").replace(/\s*÷\s*/g, "/").replace(/−/g, "-")
            .replace(/∞/g, "inf")
    }

    // График: plot(…) как в qalc, но точки считает genvector, а рисует
    // лончер (PlotView), без gnuplot. Первый аргумент — выражение, вектор
    // выражений (несколько линий), вектор чисел (y по номерам) или матрица
    // пар x y; дальше от, до и опции qalc (samples, step, variable, style,
    // smooth, ymin, ymax, xlog, ylog, complex, linewidth, legend, title…).
    // callback({series: [{label, xs, ys, th?, r?, im?, fn?}], min, max, opts}) или null
    function plot(text, callback) {
        const m = text.trim().match(/^plot\s*\(([\s\S]*)$/i)
        if (!m) { callback(null); return }
        // Закрывающую скобку plot( … ) можно не дописывать
        let body = m[1]
        if ((body.match(/\(/g) ?? []).length < (body.match(/\)/g) ?? []).length)
            body = body.replace(/\)\s*$/, "")
        if (hasSideEffects(body)) { callback(null); return }
        const args = _splitArgs(body)
        // Опция на месте пределов (plot([1 2 3], boxes)) — qalc тут ругается,
        // а мы считаем пределы пропущенными
        const optAt = args.findIndex((a, i) => i > 0 && i < 3 && _isPlotOption(a))
        if (optAt > 0) args.splice(optAt, 0, ...Array(3 - optAt).fill(""))
        const o = _plotOptions(args.slice(3))
        const a0 = _stripY((args[0] ?? "").trim())
        if (a0 === "") { callback(null); return }

        // Переменная графика уходит в qalc «неизвестной» \<буква>: иначе
        // переменная x = 42 превратит график в прямую. Буква — та же или
        // любая, которой в выражении нет, чтобы не спутать с чужими x, y…
        const v = o.variable
        // Перед именем может стоять цифра (3x — это 3·x), но не буква;
        // «\x» qalc — та же переменная
        const word = w => new RegExp("(^|[^\\\\A-Za-z_])\\\\?" + w.replace(/\W/g, "\\$&") + "(?!\\w)", "g")
        const hasVar = s => word(v).test(s)
        const sym = v.length === 1 && /[a-z]/i.test(v) ? v
            : "xtuvwsabcdpq".split("").find(c => !word(c).test(body)) ?? "x"
        const subst = (s, by) => s.replace(word(v), (_, pre) => pre + by)

        // Линии: функции переменной и наборы данных — в порядке, как написаны
        let specs
        const inner = _bracketInner(a0)
        if (inner !== null && !_hasTopLevel(inner, ";")) {
            const elems = _vectorElements(inner).map(e => _stripY(e.trim())).filter(e => e !== "")
            specs = elems.some(e => hasVar(e) || e.startsWith("["))
                ? elems.map(e => hasVar(e) ? { fn: e } : { data: e })
                : [{ data: a0 }]
        } else {
            specs = [hasVar(a0) ? { fn: a0 } : { data: a0 }]
        }
        const fns = specs.filter(s => s.fn !== undefined)
        const datas = specs.filter(s => s.data !== undefined)

        // Все числа из аргументов (пределы, шаг, ymin/ymax) считает qalc одним
        // запросом: «2pi», «-e» и т.п. тоже годятся. Пустой предел — по умолчанию
        const arg = (a, d) => _decimalComma((a ?? "").trim()) || d
        const nums = [arg(args[1], "-10"), arg(args[2], "10"), o.step || "0",
                      o.ymin || "0", o.ymax || "0"]
        evaluate("[" + nums.map(s => "(" + s + ")").join(", ") + "]", res => {
            const n = _parseVector(res).map(c => c.im === 0 ? c.re : NaN)
            if (n.length !== 5) { callback(null); return }
            let [lo, hi, step] = n
            if (fns.length > 0 && (!isFinite(lo) || !isFinite(hi) || lo === hi)) { callback(null); return }
            if (lo > hi) [lo, hi] = [hi, lo]
            o.yLo = o.ymin ? n[3] : NaN
            o.yHi = o.ymax ? n[4] : NaN

            let waiting = (fns.length > 0 ? 1 : 0) + datas.length
            let failed = false
            const done = ok => {
                if (!ok) failed = true
                if (--waiting > 0) return
                // flatMap в движке QML нет
                const series = failed ? [] : specs.reduce((a, s) => a.concat(s.result ?? []), [])
                if (series.length === 0 || series.every(s => s.ys.every(y => !isFinite(y)))) {
                    callback(null)
                    return
                }
                // Полярный: x — угол, y — радиус
                if (o.style === "polar")
                    for (const s of series) {
                        s.th = s.xs
                        s.r = s.ys
                        s.xs = s.th.map((t, i) => s.r[i] * Math.cos(t))
                        s.ys = s.th.map((t, i) => s.r[i] * Math.sin(t))
                    }
                callback({ series: series, min: lo, max: hi, opts: o })
            }

            // Функции — одним genvector на все: строки — x, столбцы — линии.
            // xlog — точки равномерно по логарифму, иначе слева их почти нет
            if (fns.length > 0) {
                const logX = o.xlog && lo > 0
                const useStep = step > 0 && !logX && (hi - lo) / step <= 5000
                const L = logX ? Math.log10(lo) : lo, H = logX ? Math.log10(hi) : hi
                const samples = Math.max(2, Math.min(5000, o.samples || 241))
                const exprs = fns.map(s => _decimalComma(subst(s.fn, logX ? "(10^\\" + sym + ")" : "\\" + sym)))
                const vec = exprs.length === 1 ? exprs[0] : "[" + exprs.join(", ") + "]"
                evaluate("matrix2vector(genvector(" + vec + ", " + L + ", " + H + ", "
                         + (useStep ? step : samples) + ", \\" + sym + (useStep ? ", 1" : "") + "))", r => {
                    const vals = r === "" ? [] : _parseVector(r)
                    const k = fns.length, rows = vals.length / k
                    if (rows < 1 || rows !== Math.floor(rows)) { done(false); return }
                    const xs = Array.from({ length: rows }, (_, i) => {
                        const t = useStep ? L + step * i : L + (H - L) * i / Math.max(1, rows - 1)
                        return logX ? Math.pow(10, t) : t
                    })
                    fns.forEach((s, j) => {
                        const col = Array.from({ length: rows }, (_, i) => vals[i * k + j])
                        // Без complex комплексные значения — дыры, как у qalc
                        s.result = [{ label: s.fn, xs: xs, fn: true,
                                      ys: col.map(c => c.im === 0 || o.complex ? c.re : NaN) }]
                        // С complex — ещё и мнимая часть, пунктиром того же цвета
                        if (o.complex && col.some(c => c.im !== 0 && isFinite(c.im)))
                            s.result.push({ label: "Im " + s.fn, xs: xs, fn: true, im: true,
                                            ys: col.map(c => c.im) })
                    })
                    done(true)
                })
            }

            // Данные: размер и числа построчно, разбираем, когда придёт и то, и другое
            const many = specs.length > 1
            const counters = { vector: 0, matrix: 0 }
            for (const s of datas) {
                const e = _decimalComma(s.data)
                const got = {}
                const both = () => {
                    if (got.dims === undefined || got.vals === undefined) return
                    // Число, а не набор, — горизонтальной линией, как у qalc
                    const c = got.vals[0]
                    if (got.vals.length === 1 && c.im === 0 && isFinite(lo) && isFinite(hi) && lo < hi)
                        s.result = [{ label: s.data, xs: [lo, hi], ys: [c.re, c.re], fn: true }]
                    else
                        s.result = _dataSeries(s.data, got.dims, got.vals, many, counters)
                    done(true)
                }
                evaluate("[rows(" + e + "), columns(" + e + ")]", r => {
                    const d = _parseVector(r).map(c => c.re)
                    got.dims = d.length === 2 ? d : [0, 0]
                    both()
                })
                evaluate("matrix2vector(" + e + ")", r => {
                    got.vals = r === "" ? [] : _parseVector(r)
                    both()
                })
            }
        })
    }

    // Набор данных → линии, как у qalc: матрица из двух столбцов — пары x y,
    // вектор — y по номерам, матрица шире — каждая строка своей линией
    function _dataSeries(src, dims, cvals, many, counters) {
        const [rows, cols] = dims
        const vals = cvals.map(c => c.im === 0 ? c.re : NaN)
        if (vals.length === 0 || rows * cols !== vals.length) return []
        const name = (kind, word) => {
            const i = ++counters[kind]
            return many ? word + (i > 1 ? " " + i : "") : src
        }
        if (cols === 2 && rows > 1)
            return [{ label: name("matrix", "Матрица"), data: true,
                      xs: vals.filter((_, i) => i % 2 === 0), ys: vals.filter((_, i) => i % 2 === 1) }]
        if (rows === 1 || cols === 1)
            return [{ label: name("vector", "Вектор"), data: true,
                      xs: vals.map((_, i) => i + 1), ys: vals }]
        const out = []
        for (let r = 0; r < rows; r++)
            out.push({ label: "Строка " + (r + 1), data: true,
                       xs: Array.from({ length: cols }, (_, i) => i + 1),
                       ys: vals.slice(r * cols, (r + 1) * cols) })
        return out
    }

    // Опции plot() после пределов — как их понимает qalc: «имя значение» одним
    // аргументом или двумя, у флагов значение можно опустить, у именованных
    // значений — имя опции; первое число — samples (целое > 10) или step
    readonly property var _plotNames: [
        ["persistent", "persistent"], ["smoothing", "smooth"], ["smooth", "smooth"],
        ["style", "style"], ["type", "style"], ["step size", "step"], ["step", "step"],
        ["samples", "samples"], ["rate", "samples"], ["color", "color"], ["grid", "grid"],
        ["title", "title"], ["legend", "legend"], ["key", "legend"],
        ["y-label", "ylabel"], ["y label", "ylabel"], ["ylabel", "ylabel"],
        ["x-label", "xlabel"], ["x label", "xlabel"], ["xlabel", "xlabel"],
        ["line width", "linewidth"], ["linewidth", "linewidth"], ["lw", "linewidth"],
        ["monochrome", "mono"], ["mono", "mono"],
        ["y-min", "ymin"], ["y min", "ymin"], ["ymin", "ymin"],
        ["y-max", "ymax"], ["y max", "ymax"], ["ymax", "ymax"],
        ["logscale y", "ylog"], ["y-log", "ylog"], ["y log", "ylog"], ["ylog", "ylog"],
        ["logscale x", "xlog"], ["x-log", "xlog"], ["x log", "xlog"], ["xlog", "xlog"],
        ["logscale", "logscale"], ["variable", "variable"], ["var", "variable"],
        ["complex", "complex"], ["real", "real"]
    ]
    readonly property var _plotStyles: ["lines", "points", "linespoints", "boxes", "histogram",
                                        "steps", "candlesticks", "dots", "polar"]
    readonly property var _plotLegends: ["none", "top-left", "top-right", "bottom-left",
                                         "bottom-right", "below", "outside"]

    function _plotOptions(list) {
        const o = { variable: "x", style: "lines", smooth: "none", samples: 0, step: "",
                    ymin: "", ymax: "", xlog: false, ylog: false, complex: false, grid: true,
                    mono: false, linewidth: 0, legend: "", title: "", xlabel: "", ylabel: "" }
        const flag = v => v === "" || Number(v) !== 0
        const style = v => {
            const s = { histeps: "histogram", bars: "boxes" }[v] ?? v
            if (_plotStyles.includes(s)) return s
            const i = Number(v)
            return Number.isInteger(i) && i >= 0 && i < 8 ? _plotStyles[i] : ""
        }
        const smooth = v => ({ none: "none", "0": "none", splines: "splines", csplines: "splines",
                               "1": "splines", bezier: "bezier", "2": "bezier" })[v] ?? ""
        const legend = v => {
            const s = v.replace(/\s+/g, "-").replace(/^(top|bottom)(left|right)$/, "$1-$2")
            if (_plotLegends.includes(s)) return s
            const i = Number(v)
            return Number.isInteger(i) && i >= 0 && i < 6 ? _plotLegends[i] : ""
        }
        const apply = (key, raw) => {
            const v = raw.trim().toLowerCase()
            switch (key) {
            case "samples": if (Number(v) >= 1) o.samples = Math.round(Number(v)); o.step = ""; break
            case "step": o.step = raw.trim() || "1"; break
            case "variable":
                o.variable = ({ "0": "x", "1": "y", "2": "z" })[v] ?? raw.trim().replace(/^\\/, "")
                break
            case "style": o.style = style(v) || (v === "" ? "points" : o.style); break
            case "smooth": o.smooth = smooth(v) || (v === "" ? "splines" : o.smooth); break
            case "legend": o.legend = legend(v) || (v === "" ? "below" : o.legend); break
            case "ymin": o.ymin = raw.trim(); break
            case "ymax": o.ymax = raw.trim(); break
            case "xlog": o.xlog = flag(v); break
            case "ylog": o.ylog = flag(v); break
            case "logscale": o.xlog = o.ylog = flag(v); break
            case "complex": o.complex = flag(v); break
            case "real": o.complex = !flag(v); break
            case "grid": o.grid = flag(v); break
            case "mono": o.mono = flag(v); break
            case "color": o.mono = !flag(v); break
            case "linewidth": if (Number(v) > 0 && Number(v) < 100) o.linewidth = Number(v); break
            case "title": case "xlabel": case "ylabel":
                o[key] = raw.trim().replace(/^"(.*)"$/, "$1").replace(/^'(.*)'$/, "$1")
                break
            }
        }
        // Флаги, которые включаются одним именем
        const valueless = ["persistent", "smooth", "style", "grid", "legend", "xlog", "ylog",
                           "logscale", "complex", "real", "mono", "color"]
        const textual = ["title", "xlabel", "ylabel"]
        let pending = ""
        list.forEach((a, idx) => {
            const s = a.trim()
            if (s === "") return
            if (textual.includes(pending)) { apply(pending, s); pending = ""; return }
            const low = s.toLowerCase()
            const hit = _plotNames.find(([n]) => low === n || low.startsWith(n + " "))
            if (hit) {
                const rest = s.slice(hit[0].length).trim()
                if (rest !== "") { apply(hit[1], rest); pending = "" }
                else {
                    if (valueless.includes(hit[1])) apply(hit[1], "")
                    pending = hit[1]
                }
                return
            }
            if (pending !== "") { apply(pending, s); pending = ""; return }
            // Значение без имени: стиль, сглаживание, легенда, переменная, число
            if (style(low) && isNaN(Number(low))) o.style = style(low)
            else if (smooth(low) && isNaN(Number(low))) o.smooth = smooth(low)
            else if (legend(low) && isNaN(Number(low))) o.legend = legend(low)
            else if (/^\\?[xyz]$/.test(low)) o.variable = low.replace("\\", "")
            else if (idx === 0) {
                const num = Number(_plainNum(s))
                if (Number.isInteger(num) && num > 10) o.samples = num
                else o.step = s
            }
        })
        return o
    }

    function _isPlotOption(a) {
        const low = a.trim().toLowerCase()
        return low !== "" && (_plotNames.some(([n]) => low === n || low.startsWith(n + " "))
            || _plotStyles.includes(low) || ["histeps", "bars", "splines", "csplines", "bezier"].includes(low)
            || _plotLegends.includes(low))
    }

    // "y = x^2" → "x^2", как у qalc
    function _stripY(s) {
        return s.replace(/^y\s*=(?!=)\s*/, "")
    }

    // "[…]" целиком в одних скобках → содержимое, иначе null
    function _bracketInner(s) {
        if (!s.startsWith("[") || !s.endsWith("]")) return null
        let depth = 0
        for (let i = 0; i < s.length; i++) {
            if (s[i] === "[" || s[i] === "(") depth++
            else if (s[i] === "]" || s[i] === ")") depth--
            if (depth === 0 && i < s.length - 1) return null
        }
        return s.slice(1, -1)
    }

    function _hasTopLevel(s, ch) {
        let depth = 0
        for (const c of s) {
            if (c === "(" || c === "[") depth++
            else if (c === ")" || c === "]") depth--
            else if (c === ch && depth === 0) return true
        }
        return false
    }

    // Элементы вектора: через запятую, а без запятых — через пробел, как
    // в qalc: «[x^2 -x]» — два элемента, «[x - 2]» и «[x ^2]» — один
    function _vectorElements(inner) {
        if (_hasTopLevel(inner, ",")) return _splitArgs(inner)
        const chunks = []
        let depth = 0, cur = ""
        for (const c of inner) {
            if (c === "(" || c === "[") depth++
            else if (c === ")" || c === "]") depth--
            if (/\s/.test(c) && depth === 0) {
                if (cur !== "") chunks.push(cur)
                cur = ""
            } else cur += c
        }
        if (cur !== "") chunks.push(cur)
        const out = []
        const op = /[-+*\/^×·÷=<>%]$/
        for (const ch of chunks) {
            const joins = out.length > 0 && (op.test(out[out.length - 1])
                || /^[+*\/^×·÷=<>%]/.test(ch) || /^[-−]$/.test(ch))
            if (joins) out[out.length - 1] += " " + ch
            else out.push(ch)
        }
        return out
    }

    // Ответ qalc «[a  b  (c + di)  (1 / 0)…]» → [{re, im}]; не число — NaN
    function _parseVector(res) {
        let s = res.trim()
        if (s.startsWith("[") && s.endsWith("]")) s = s.slice(1, -1)
        const out = []
        let depth = 0, cur = ""
        for (const c of s) {
            if (c === "(" || c === "[") depth++
            else if (c === ")" || c === "]") depth--
            if (/\s/.test(c) && depth === 0) {
                if (cur !== "") out.push(_parseComplex(cur))
                cur = ""
            } else cur += c
        }
        if (cur !== "") out.push(_parseComplex(cur))
        return out
    }

    function _parseComplex(tok) {
        let t = _plainNum(tok).replace(/\s+/g, "")
        while (t.startsWith("(") && t.endsWith(")")) t = t.slice(1, -1)
        const num = "(?:\\d+\\.?\\d*|\\.\\d+)(?:e[-+]?\\d+)?"
        let m
        if (new RegExp("^[-+]?" + num + "$").test(t)) return { re: Number(t), im: 0 }
        if (/^[-+]?∞$/.test(t)) return { re: t.startsWith("-") ? -Infinity : Infinity, im: 0 }
        if ((m = t.match(new RegExp("^([-+]?)(" + num + ")?i$"))))
            return { re: 0, im: (m[1] === "-" ? -1 : 1) * (m[2] ? Number(m[2]) : 1) }
        if ((m = t.match(new RegExp("^([-+]?" + num + ")([-+])(" + num + ")?i$"))))
            return { re: Number(m[1]), im: (m[2] === "-" ? -1 : 1) * (m[3] ? Number(m[3]) : 1) }
        return { re: NaN, im: 0 }
    }

    // Аргументы через запятую/точку с запятой — только верхнего уровня скобок
    function _splitArgs(s) {
        const out = []
        let depth = 0, cur = ""
        for (const c of s) {
            if (c === "(" || c === "[") depth++
            else if (c === ")" || c === "]") depth--
            if ((c === "," || c === ";") && depth === 0) { out.push(cur); cur = "" }
            else cur += c
        }
        out.push(cur)
        return out
    }

    // Число для подписи: без хвоста двоичной погрешности (0.30000000000000004)
    function fmtNum(v) {
        return String(Number(v.toPrecision(6)))
    }

    function _plainNum(v) {
        return v.trim().replace(/−/g, "-").replace(/×10\^/g, "e").replace(/E/g, "e")
    }

    function setAns(v) {
        ans = v
    }

    function setVar(name, value) {
        const v = Object.assign({}, vars)
        v[name] = value
        vars = v
        _defineVar(name, value)
        _saveVars()
    }

    function removeVar(name) {
        const v = Object.assign({}, vars)
        delete v[name]
        vars = v
        if (proc.running)
            proc.write("delete " + name + "\n")
        _saveVars()
    }

    function _defineVar(name, value) {
        if (proc.running)
            proc.write(name + " := (" + value + ')\n"@@0"\n')
    }

    function _saveVars() {
        varsView.setText(JSON.stringify(vars, null, 1) + "\n")
    }

    function _onLine(raw) {
        // SplitParser иногда отдаёт куски с переводами строк внутри
        for (const l of raw.split(/\r?\n/))
            _onLineOne(l)
    }

    function _onLineOne(raw) {
        const line = raw.replace(/\x1b\[[0-9;?]*[@-~]/g, "").replace(/\r/g, "")
        // Эхо ввода: выражение начинает новый ответ, эхо маркера и пустой строки пропускаем
        if (/^>\s*$/.test(line))
            return
        if (line.startsWith("> ")) {
            if (!line.startsWith('> "@@'))
                _lines = []
            return
        }
        const m = line.trim().match(/^@@(\d+)$/)
        if (m) {
            const id = Number(m[1])
            const cb = _pending[id]
            delete _pending[id]
            // Более ранние без ответа (маркер потерялся) — уже не придут
            for (const k of Object.keys(_pending))
                if (Number(k) < id) {
                    const old = _pending[k]
                    delete _pending[k]
                    old("")
                }
            // Последний непустой кусок до маркера — ответ на выражение
            const res = _lines.filter(l => l.trim() !== "").map(l => l.trim()).join(" ")
            _lines = []
            if (cb) cb(res)
            return
        }
        _lines.push(line)
    }

    readonly property string sandbox: Quickshell.shellPath("assets/launcher/qalc-sandbox.sh")

    // qalc живёт в песочнице bubblewrap: без сети, с пустой домашней папкой
    // и конфигом только на чтение — даже если что-то в выражении (своя функция
    // с command() и т.п.) попробует запустить программу, ей некуда дотянуться
    Process {
        id: proc
        command: ["bash", root.sandbox, "-t",
            "-s", "color 0", "-s", "save mode no", "-s", "save definitions no",
            "-s", "save config no",
            // С русской локалью qalc считает запятую десятичной: max(1,2) → 1,2,
            // а числа выводит как 0,5 — и график их не разбирает. Внутри всегда
            // точка, а «0,5» пользователя переводит _decimalComma()
            "-s", "decimal comma off",
            "-s", "upxrates 0", "-s", "unicode 1",
            // Обычный ответ — всегда десятичный, точный считается отдельно
            "-s", "approx approximate", "-s", "fr 0"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root._onLine(data)
        }
        onStarted: {
            root.ready = true
            for (const k of Object.keys(root.vars))
                root._defineVar(k, root.vars[k])
        }
        onExited: {
            root.ready = false
            // Отвалившиеся запросы — пустой ответ
            for (const id of Object.keys(root._pending))
                root._pending[id]("")
            root._pending = {}
            restartTimer.start()
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: {
            interval = 2000
            proc.running = true
        }
    }

    // Курсы валют: раз в 3 часа — отдельным коротким qalc, которому песочница
    // даёт сеть и запись только в каталог данных qalc. Скрипт сам пропускает
    // скачивание, если курсам меньше 3 часов (код 3). Скачали — перезапускаем
    // демон, курсы он читает только при старте
    readonly property int ratesMinutes: 180

    Process {
        id: rates
        command: ["bash", root.sandbox, "--rates", String(root.ratesMinutes - 5),
            "-e", "-t", "-s", "save mode no", "-s", "save config no", "1"]
        onExited: (code, _status) => {
            if (code === 0 && proc.running) {
                restartTimer.interval = 200
                proc.running = false
            }
        }
    }
    Timer {
        interval: root.ratesMinutes * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: rates.running = true
    }

    FileView {
        id: varsView
        path: root.varsFile
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const v = JSON.parse(text())
                if (v && typeof v === "object")
                    root.vars = v
            } catch (e) {}
            for (const k of Object.keys(root.vars))
                root._defineVar(k, root.vars[k])
        }
    }

    Component.onCompleted: proc.running = true
}
