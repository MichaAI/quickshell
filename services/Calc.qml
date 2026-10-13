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

    // График: plot(f, от, до) → точки через genvector, без gnuplot.
    // callback({f, min, max, xs, ys}) или null
    function plot(text, callback) {
        const m = text.trim().match(/^plot\s*\((.*)$/i)
        if (!m) { callback(null); return }
        // Закрывающую скобку plot( … ) можно не дописывать
        let body = m[1]
        if ((body.match(/\(/g) ?? []).length < (body.match(/\)/g) ?? []).length)
            body = body.replace(/\)\s*$/, "")
        const args = _splitArgs(body)
        const f = (args[0] ?? "").trim()
        // Недописанный предел — по умолчанию, а не 0
        const num = (a, d) => (a ?? "").trim() === "" ? d : Number(_plainNum(_decimalComma(a)))
        let lo = num(args[1], -10), hi = num(args[2], 10)
        if (f === "" || hasSideEffects(f) || isNaN(lo) || isNaN(hi) || lo === hi) { callback(null); return }
        if (lo > hi) [lo, hi] = [hi, lo]
        const n = 241
        // \x — «неизвестная x» в qalc: иначе переменная x = 42 превратит график в прямую
        const fx = f.replace(/(^|[^\\\w])x(?!\w)/g, "$1\\x")
        evaluate("genvector(" + fx + ", " + lo + ", " + hi + ", " + n + ", \\x)", res => {
            const ys = res.replace(/^\[|\]$/g, "").trim().split(/\s+/).map(v => Number(_plainNum(v)))
            if (ys.length !== n || ys.every(y => !isFinite(y))) { callback(null); return }
            const xs = ys.map((_, i) => lo + (hi - lo) * i / (n - 1))
            callback({ f: f, min: lo, max: hi, xs: xs, ys: ys })
        })
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
