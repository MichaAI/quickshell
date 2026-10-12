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

    function _prepare(expr) {
        let e = expr.replace(/[\r\n]+/g, " ").trim()
        // "15% of 200" — qalc его не понимает
        e = e.replace(/(\d+(?:\.\d+)?)\s*%\s*(?:of|от)\s+/gi, "($1/100) * ")
        e = e.replace(/\bans\b/g, "(" + (ans !== "" ? ans : "0") + ")")
        // "to mi" → "to -mi": без смешанных единиц (6 mi + 376 yd + …)
        e = e.replace(/(\s(?:to|in|as)\s+)([a-zA-Z]+)\s*$/, (m, pre, unit) =>
            _formats.includes(unit.toLowerCase()) ? m : pre + "-" + unit)
        return e
    }

    // Посчитать: callback(result) — строка или "" при ошибке. Возвращает id.
    function evaluate(expr, callback) {
        const e = _prepare(expr)
        const first = e.split(/[\s(]/)[0]
        if (e === "" || _commands.includes(first) || e.startsWith('"')) {
            callback("")
            return -1
        }
        if (!proc.running) {
            callback("")
            return -1
        }
        const id = ++_seq
        _pending[id] = callback
        proc.write(e + '\n"@@' + id + '"\n')
        return id
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
        // Эхо ввода: выражение начинает новый ответ, эхо маркера пропускаем
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
            // Последний непустой кусок до маркера — ответ на выражение
            const res = _lines.filter(l => l.trim() !== "").map(l => l.trim()).join(" ")
            _lines = []
            if (cb) cb(res)
            return
        }
        _lines.push(line)
    }

    Process {
        id: proc
        command: ["qalc", "-t",
            "-s", "color 0", "-s", "save mode no", "-s", "save definitions no",
            "-s", "upxrates 0", "-s", "unicode 1"]
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
        onTriggered: proc.running = true
    }

    // Курсы валют: раз в сутки просим сам qalc их скачать
    Timer {
        interval: 24 * 3600 * 1000
        running: root.ready
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.write("exrates\n")
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
