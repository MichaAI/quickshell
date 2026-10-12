pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import "../.."
import "../../services"
import "../../components"
import "../../components/Colors.js" as Colors

// Лончер — выпадающее меню из бара. Кроме приложений умеет режимы по префиксу:
//   =  калькулятор (qalc)      $  переменные калькулятора
//   >  команда zsh             :  окна niri
//   !  действия                #  буфер обмена (и цвета #rrggbb)
//   ~  файлы, ~/ и / — пути    ;  эмодзи и nerd-иконки
//   kill …  процессы
// Автодополнение везде одинаковое: серый хвост принимается →,
// Tab подставляет выбранный пункт списка.
Item {
    id: root

    implicitWidth: 620
    implicitHeight: 480

    property string query: ""
    property int selIdx: 0

    // Подрежим поверх обычного: null | {kind: "actions", app} | {kind: "picker", back}
    property var sub: null

    // ===== Режим по префиксу =====

    readonly property var modes: ({
        apps:    { icon: "󰍉", color: Theme.mauve,    hint: "Поиск приложений…   (= > : ! # ~ ; $ kill)" },
        calc:    { icon: "󰃬", color: Theme.peach,    hint: "Выражение: 2^10, 10 km to mi, x = 42, plot(sin(x))…" },
        vars:    { icon: "󰫧", color: Theme.peach,    hint: "Переменные калькулятора" },
        shell:   { icon: "󰆍", color: Theme.green,    hint: "Команда zsh…" },
        windows: { icon: "", color: Theme.blue,     hint: "Открытые окна…" },
        actions: { icon: "󰐥", color: Theme.red,      hint: "Действия: питание, скриншоты, пипетка…" },
        clip:    { icon: "󰅍", color: Theme.yellow,   hint: "Буфер обмена… (#rrggbb — цвет)" },
        files:   { icon: "󰈞", color: Theme.sapphire, hint: "Поиск файлов в ~…" },
        path:    { icon: "", color: Theme.sapphire, hint: "Путь…" },
        glyphs:  { icon: "󰞅", color: Theme.pink,     hint: "Эмодзи и иконки: кот, heart, nf-md-cat…" },
        kill:    { icon: "󰆴", color: Theme.red,      hint: "Процесс…" },
        picker:  { icon: "󰏘", color: Theme.pink,     hint: "Цвет: #hex, rgb(), hsl()…" },
        history: { icon: "󰋚", color: Theme.lavender, hint: "Поиск по истории запросов…" }
    })

    readonly property var parsed: {
        const q = query
        if (sub && sub.kind === "picker") return { mode: "picker", arg: q, cut: 0 }
        if (sub && sub.kind === "history") return { mode: "history", arg: q, cut: 0 }
        if (/^kill\s/.test(q)) return { mode: "kill", arg: q.slice(5).trim(), cut: 5 }
        switch (q.charAt(0)) {
        case "=": return { mode: "calc", arg: q.slice(1), cut: 1 }
        case "$": return { mode: "vars", arg: q.slice(1).trim(), cut: 1 }
        case ">": return { mode: "shell", arg: q.slice(1).replace(/^\s+/, ""), cut: q.length - q.slice(1).replace(/^\s+/, "").length }
        case ":": return { mode: "windows", arg: q.slice(1).trim(), cut: 1 }
        case "!": return { mode: "actions", arg: q.slice(1).trim(), cut: 1 }
        case "#": return { mode: "clip", arg: q.slice(1), cut: 1 }
        case ";": return { mode: "glyphs", arg: q.slice(1).trim(), cut: 1 }
        case "/": return { mode: "path", arg: q, cut: 0 }
        case "~":
            if (q.startsWith("~/")) return { mode: "path", arg: q, cut: 0 }
            return { mode: "files", arg: q.slice(1).trim(), cut: 1 }
        }
        return { mode: "apps", arg: q, cut: 0 }
    }
    readonly property string mode: parsed.mode
    readonly property string arg: parsed.arg
    readonly property var modeInfo: modes[mode]

    // ===== Поиск =====

    // Оценка совпадения: начало > начало слова > подстрока > подпоследовательность
    function score(text, q) {
        if (q === "") return 1
        const t = (text ?? "").toLowerCase()
        if (t.startsWith(q)) return 100
        if (t.includes(" " + q) || t.includes("-" + q) || t.includes("." + q)) return 80
        if (t.includes(q)) return 60
        let i = 0
        for (const ch of t)
            if (ch === q[i]) i++
        return i === q.length ? 10 : 0
    }

    function filterBy(list, q, fields) {
        const lq = q.toLowerCase()
        // Индекс — чтобы при равных очках сохранялся исходный порядок
        return list
            .map((x, i) => [Math.max(...fields(x).map(f => score(f, lq))), x, i])
            .filter(x => x[0] > 0)
            .sort((a, b) => b[0] - a[0] || a[2] - b[2])
            .map(x => x[1])
    }

    // ===== Приложения =====

    readonly property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)

    function appScore(app, q) {
        const s = score(app.name, q)
        if (s >= 60) return s
        const g = score(app.genericName ?? "", q)
        if (g >= 60) return 30
        if (score(Array.from(app.keywords ?? []).join(" "), q) >= 60) return 25
        if (score(app.comment ?? "", q) >= 60) return 20
        return s
    }

    // Рейтинг: частота запусков (аналог кэша wofi)
    property var counts: ({})
    readonly property string histFile: Quickshell.env("HOME") + "/.cache/quickshell-launcher-hist"

    Process {
        id: histRead
        command: ["cat", root.histFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const c = {}
                for (const l of this.text.split("\n"))
                    if (l !== "") c[l] = (c[l] ?? 0) + 1
                root.counts = c
            }
        }
    }
    Process { id: histWrite }

    function launchApp(app, action) {
        histWrite.exec(["sh", "-c", 'printf "%s\\n" "$1" >> "$2"', "qs", app.id, root.histFile])
        if (action)
            action.execute()
        else
            app.execute()
        Ui.closePopouts()
    }

    function appItem(app) {
        const hasActions = Array.from(app.actions ?? []).length > 0
        return {
            icon: Quickshell.iconPath(app.icon, "application-x-executable"),
            title: app.name,
            sub: app.genericName || app.comment || "",
            badge: hasActions ? "Tab  󰁔" : "",
            ghostSource: app.name,
            run: () => launchApp(app, null),
            tab: hasActions ? () => openActions(app) : null
        }
    }

    function appResults(q) {
        const lq = q.toLowerCase().trim()
        const freq = a => counts[a.id] ?? 0
        if (lq === "")
            return [...apps].sort((a, b) =>
                freq(b) - freq(a) || a.name.localeCompare(b.name)).map(appItem)
        return apps
            .map(a => [appScore(a, lq), a])
            .filter(x => x[0] > 0)
            .sort((x, y) => (y[0] + freq(y[1]) * 5) - (x[0] + freq(x[1]) * 5)
                || x[1].name.localeCompare(y[1].name))
            .map(x => appItem(x[1]))
    }

    function openActions(app) {
        sub = { kind: "actions", app: app }
        selIdx = 0
    }

    // ===== Калькулятор =====

    property var calc: ({ input: "", value: "", exact: "", assign: "" })
    property int calcToken: 0

    function calcExpr() {
        if (mode === "calc") return arg.trim()
        if (mode === "apps" && Calc.looksLikeMath(arg)) return arg.trim()
        return ""
    }

    property var plotData: null

    function requestCalc() {
        const e = calcExpr()
        if (e === "") {
            calc = { input: "", value: "", exact: "", assign: "" }
            plotData = null
            return
        }
        // plot(…) — рисуем сами, без отдельного окна gnuplot
        if (/^plot\s*\(/i.test(e)) {
            calc = { input: "", value: "", exact: "", assign: "" }
            const token = ++calcToken
            Calc.plot(e, d => {
                if (token !== root.calcToken) return
                root.plotData = d ? Object.assign({ input: e }, d) : null
            })
            return
        }
        plotData = null
        const asg = Calc.parseAssign(e)
        const expr = asg ? asg.expr : e
        const token = ++calcToken
        Calc.evaluate(expr, res => {
            if (token !== root.calcToken) return
            // Пустой ответ или «эхо» без вычисления — не показываем в общем поиске
            const same = res.replace(/\s/g, "") === expr.replace(/\s/g, "")
            root.calc = {
                input: e,
                value: (mode === "apps" && same) ? "" : res,
                exact: "",
                assign: asg ? asg.name : ""
            }
        })
        // Точный ответ — вторым запросом, тем же токеном
        if (!asg)
            Calc.evaluate(expr, res => {
                if (token !== root.calcToken || root.calc.input !== e) return
                root.calc = Object.assign({}, root.calc, { exact: res })
            }, true)
    }

    // Точный ответ стоит показывать, только если он отличается от обычного
    // и в ответе нет единиц/валют — "(78125/12573) mi" никому не нужен
    function exactDiffers() {
        const n = x => x.replace(/\s/g, "")
        const units = calc.value.replace(/\b[a-zA-Z]\s*[=≈]|\bor\b/g, "").replace(/\d[eE][-−+]?\d/g, "0")
        return calc.exact !== "" && calc.value !== "" && calc.assign === ""
            && n(calc.exact) !== n(calc.value)
            && !/[a-zA-Z€$£¥₽°"]/.test(units)
    }

    function calcItems() {
        const out = []
        if (plotData && plotData.input === calcExpr())
            out.push({
                plot: plotData,
                glyph: "󰄧",
                title: "y = " + plotData.f,
                sub: "x от " + plotData.min + " до " + plotData.max,
                badge: "⏎ открыть в gnuplot",
                run: () => {
                    Quickshell.execDetached(["qalc", plotData.input])
                    Ui.closePopouts()
                }
            })
        if (calc.value !== "" && calc.input === calcExpr()) {
            const asg = calc.assign
            out.push({
                big: true,
                glyph: asg ? "󰫧" : "󰃬",
                glyphColor: Theme.peach,
                title: asg ? asg + " = " + calc.value : calc.value,
                sub: asg ? "⏎ сохранить переменную" : calc.input,
                badge: asg ? "" : "⏎ копировать   ⇧⏎ в ans",
                run: shift => {
                    if (asg) {
                        Calc.setVar(asg, calc.value)
                        searchInput.text = "$"
                    } else if (shift) {
                        Calc.setAns(calc.value)
                        searchInput.text = "=ans"
                    } else {
                        // Копируем в виде, который вставится куда угодно: −5 → -5
                        Calc.setAns(calc.value)
                        Tools.copy(Calc.plain(calc.value))
                        Ui.closePopouts()
                    }
                }
            })
            if (exactDiffers())
                out.push({
                    big: true,
                    glyph: "√",
                    glyphColor: Theme.peach,
                    title: calc.exact,
                    sub: "Точный ответ   ·   " + Calc.plain(calc.exact),
                    badge: "⏎ копировать   ⇧⏎ как текст",
                    run: shift => {
                        Calc.setAns(calc.value)
                        Tools.copy(shift ? Calc.plain(calc.exact) : calc.exact)
                        Ui.closePopouts()
                    }
                })
        }
        return out
    }

    // Имена для дополнения: последнее «слово» выражения
    function calcWord() {
        const m = arg.match(/[a-zA-Z_][a-zA-Z0-9_]*$/)
        return m ? m[0] : ""
    }

    function calcNameItems() {
        const w = calcWord()
        if (w === "") return []
        return Calc.names
            .filter(n => n.toLowerCase().startsWith(w.toLowerCase()) && n !== w)
            .slice(0, 30)
            .map(n => ({
                glyph: n.endsWith("(") ? "󰊕" : Calc.vars[n] !== undefined || n === "ans" ? "󰫧" : "󰎠",
                title: n,
                sub: Calc.vars[n] !== undefined ? "= " + Calc.vars[n]
                   : n === "ans" ? "= " + (Calc.ans || "—") : "",
                badge: "Tab",
                complete: query.slice(0, query.length - w.length) + n,
                run: () => setQuery(query.slice(0, query.length - w.length) + n)
            }))
    }

    function varItems() {
        const all = Object.keys(Calc.vars).map(k => [k, Calc.vars[k]])
        if (Calc.ans !== "") all.unshift(["ans", Calc.ans])
        return filterBy(all, arg, x => [x[0]]).map(x => ({
            glyph: "󰫧",
            glyphColor: Theme.peach,
            title: x[0],
            sub: "= " + x[1],
            badge: x[0] === "ans" ? "⏎ копировать" : "⏎ копировать   ⇧Del удалить",
            ghostSource: x[0],
            complete: "=" + x[0],
            run: () => { Tools.copy(x[1]); Ui.closePopouts() },
            del: x[0] === "ans" ? null : () => Calc.removeVar(x[0])
        }))
    }

    // ===== Цвета =====

    function colorItem(text) {
        const c = Colors.parse(text)
        if (!c) return []
        return [{
            big: true,
            swatch: Qt.rgba(c.r, c.g, c.b, c.a),
            title: Colors.hex(c),
            sub: Colors.rgb(c) + "   " + Colors.hsl(c),
            badge: "⏎ колесо   ⇧⏎ копировать",
            run: shift => {
                if (shift) {
                    Tools.copy(Colors.hex(c))
                    Ui.closePopouts()
                } else {
                    openPicker(Colors.hex(c))
                }
            }
        }]
    }

    function openPicker(text) {
        sub = { kind: "picker", back: query }
        const c = Colors.parse(text) ?? { r: 0.8, g: 0.65, b: 0.97, a: 1 }
        picker.setColor(c)
        setQuery(Colors.hex(c))
    }

    // ===== Шелл =====

    property var zshItems: []
    property string zshFor: ""
    property int zshToken: 0

    function requestZsh() {
        const cmd = arg
        if (cmd.trim() === "") {
            zshItems = []
            zshFor = ""
            return
        }
        const token = ++zshToken
        Zsh.complete(cmd, items => {
            if (token !== root.zshToken) return
            root.zshItems = items
            root.zshFor = cmd
        })
    }

    // Начало текущего (последнего) слова команды
    function wordStart(cmd) {
        let i = cmd.length
        while (i > 0 && !(cmd[i - 1] === " " && cmd[i - 2] !== "\\"))
            i--
        return i
    }

    function applyZsh(word) {
        const cmd = arg
        const prefix = query.slice(0, query.length - cmd.length)
        const head = cmd.slice(0, wordStart(cmd))
        setQuery(prefix + head + word + (word.endsWith("/") || word.endsWith("=") ? "" : " "))
    }

    function shellItems() {
        const cmd = arg
        const out = []
        if (cmd.trim() !== "")
            out.push({
                glyph: "󰆍",
                glyphColor: Theme.green,
                title: cmd,
                sub: "Выполнить в фоне — вывод придёт уведомлением",
                badge: "⏎ фон   ⇧⏎ терминал",
                run: shift => runShell(cmd, shift)
            })
        for (const j of Zsh.jobs)
            out.push({
                glyph: "󰔟",
                glyphColor: Theme.yellow,
                title: j.cmd,
                sub: "Выполняется… " + Zsh.stripAnsi(j.output).trim().split("\n").pop(),
                badge: "⇧Del остановить",
                run: () => {},
                del: () => Zsh.kill(j, false)
            })
        if (cmd.trim() !== "" && zshFor === cmd) {
            for (const c of zshItems.slice(0, 80))
                out.push({
                    glyph: c.word.endsWith("/") ? "" : c.word.startsWith("-") ? "󰘵" : c.word.startsWith("$") ? "󰫧" : "󰘧",
                    glyphColor: Theme.overlay2,
                    title: c.word,
                    sub: c.desc,
                    badge: "Tab",
                    complete: true,
                    run: () => applyZsh(c.word),
                    tab: () => applyZsh(c.word)
                })
        }
        // История: подходящие команды целиком
        const lq = cmd.trim().toLowerCase()
        let n = 0
        for (const h of Zsh.history) {
            if (n >= (lq === "" ? 40 : 12)) break
            if (h === cmd || (lq !== "" && !h.toLowerCase().includes(lq))) continue
            n++
            out.push({
                glyph: "󰋚",
                glyphColor: Theme.overlay1,
                title: h.replace(/\\n/g, " ⏎ "),
                sub: "",
                badge: "⏎ запустить",
                complete: ">" + h,
                run: shift => runShell(h.replace(/\\n/g, "\n"), shift)
            })
        }
        return out
    }

    function runShell(cmd, inTerminal) {
        if (inTerminal)
            Zsh.runInTerminal(cmd)
        else
            Zsh.run(cmd)
        Ui.closePopouts()
    }

    // ===== Окна niri =====

    function windowItems() {
        const ws = {}
        for (const w of Niri.workspaces) ws[w.id] = w.idx
        return filterBy(Niri.windows, arg, w => [w.title ?? "", w.app_id ?? ""]).map(w => {
            const entry = DesktopEntries.heuristicLookup(w.app_id ?? "")
            return {
                icon: Quickshell.iconPath(entry?.icon ?? w.app_id ?? "", "application-x-executable"),
                title: w.title || w.app_id || "?",
                sub: (entry?.name ?? w.app_id ?? "") + "   ·   стол " + (ws[w.workspace_id] ?? "?")
                    + (w.is_focused ? "   ·   в фокусе" : ""),
                badge: "⏎ перейти   ⇧Del закрыть",
                ghostSource: w.title,
                run: () => { Niri.focusWindow(w.id); Ui.closePopouts() },
                del: () => Niri.closeWindow(w.id)
            }
        })
    }

    // ===== Действия =====

    property string confirmId: ""
    Process { id: actionProc }

    readonly property var actionList: [
        { id: "lock", glyph: "󰌾", title: "Заблокировать", sub: "loginctl lock-session", cmd: ["loginctl", "lock-session"] },
        { id: "suspend", glyph: "󰒲", title: "Сон", sub: "systemctl suspend", cmd: ["systemctl", "suspend"] },
        { id: "poweroff", glyph: "󰐥", title: "Выключить", sub: "systemctl poweroff", cmd: ["systemctl", "poweroff"], confirm: true },
        { id: "reboot", glyph: "󰜉", title: "Перезагрузить", sub: "systemctl reboot", cmd: ["systemctl", "reboot"], confirm: true },
        { id: "logout", glyph: "󰍃", title: "Выйти из niri", sub: "niri msg action quit", cmd: ["niri", "msg", "action", "quit", "--skip-confirmation"], confirm: true },
        { id: "monitors", glyph: "󰶐", title: "Выключить мониторы", sub: "до первого движения мыши", cmd: ["niri", "msg", "action", "power-off-monitors"] },
        { id: "shot", glyph: "󰹑", title: "Скриншот области", sub: "niri: screenshot", cmd: ["niri", "msg", "action", "screenshot"] },
        { id: "shotscreen", glyph: "󰍹", title: "Скриншот экрана", sub: "niri: screenshot-screen", cmd: ["niri", "msg", "action", "screenshot-screen"] },
        { id: "shotwin", glyph: "󱂬", title: "Скриншот окна", sub: "niri: screenshot-window", cmd: ["niri", "msg", "action", "screenshot-window"] },
        { id: "pick", glyph: "󰈊", title: "Пипетка", sub: "Взять цвет с экрана", fn: () => Tools.pickColor() },
        { id: "wheel", glyph: "󰏘", title: "Выбор цвета", sub: "Колесо, яркость, прозрачность, форматы", keep: true, fn: () => openPicker("") },
        { id: "dnd", glyph: "󰂛", title: "Не беспокоить", sub: Notifs.dnd ? "Сейчас: включено" : "Сейчас: выключено", keep: true, fn: () => Notifs.toggleDnd() },
        { id: "clearnotif", glyph: "󰎟", title: "Очистить уведомления", sub: Notifs.count + " в центре", fn: () => Notifs.clearAll() }
    ]

    function actionItems(q) {
        return filterBy(actionList, q, a => [a.title, a.id]).map(a => ({
            glyph: a.glyph,
            glyphColor: a.confirm ? Theme.red : Theme.mauve,
            title: a.title,
            sub: confirmId === a.id ? "Нажми Enter ещё раз, чтобы подтвердить" : a.sub,
            subColor: confirmId === a.id ? Theme.red : undefined,
            ghostSource: a.title,
            run: () => {
                if (a.confirm && confirmId !== a.id) {
                    confirmId = a.id
                    return
                }
                confirmId = ""
                if (!a.keep) Ui.closePopouts()
                if (a.fn) a.fn()
                else Quickshell.execDetached(a.cmd)
            }
        }))
    }

    // ===== Буфер обмена (cliphist) =====

    property var clipLines: []
    Process {
        id: clipList
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.clipLines = this.text.split("\n").filter(l => l !== "")
        }
    }

    function clipItems() {
        const lq = arg.toLowerCase()
        const out = colorItem(arg.length >= 3 ? "#" + arg : "")
        let n = 0
        for (const line of clipLines) {
            if (n >= 100) break
            const tab = line.indexOf("\t")
            const preview = line.slice(tab + 1)
            if (lq !== "" && !preview.toLowerCase().includes(lq)) continue
            n++
            const img = preview.match(/^\[\[ binary data .* (png|jpe?g|webp|gif|bmp) (\d+x\d+) \]\]$/)
            out.push({
                glyph: img ? "󰋩" : "󰅍",
                glyphColor: Theme.yellow,
                clipImage: img ? line : "",
                clipExt: img ? img[1] : "",
                title: img ? "Картинка " + img[2] : preview.replace(/\s+/g, " ").slice(0, 200),
                sub: img ? preview.replace(/^\[\[ binary data /, "").replace(/ \]\]$/, "") : "",
                badge: "⏎ копировать   ⇧Del удалить",
                run: () => {
                    Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "qs", line])
                    Ui.closePopouts()
                },
                del: () => {
                    Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist delete', "qs", line])
                    root.clipLines = root.clipLines.filter(l => l !== line)
                }
            })
        }
        return out
    }

    // ===== Файлы =====

    readonly property string home: Quickshell.env("HOME")

    function tilde(p) {
        return p.startsWith(home + "/") ? "~" + p.slice(home.length) : p
    }
    function expand(p) {
        return p.startsWith("~") ? home + p.slice(1) : p
    }

    function fileGlyph(name, isDir) {
        if (isDir) return ""
        const ext = (name.match(/\.([^.\/]+)$/)?.[1] ?? "").toLowerCase()
        const map = {
            png: "󰋩", jpg: "󰋩", jpeg: "󰋩", webp: "󰋩", gif: "󰋩", svg: "󰜡",
            mp4: "󰕧", mkv: "󰕧", webm: "󰕧", mov: "󰕧",
            mp3: "󰎆", flac: "󰎆", ogg: "󰎆", wav: "󰎆", opus: "󰎆",
            pdf: "󰈦", txt: "󰈙", md: "󰍔", doc: "󰈬", docx: "󰈬", odt: "󰈬",
            xls: "󰈛", xlsx: "󰈛", csv: "󰈛", zip: "󰗄", tar: "󰗄", gz: "󰗄", xz: "󰗄", "7z": "󰗄",
            nix: "󱄅", qml: "󰫾", js: "󰌞", ts: "󰛦", py: "󰌠", rs: "󱘗", go: "󰟓",
            c: "󰙱", cpp: "󰙲", h: "󰙱", sh: "", zsh: "", json: "󰘦", toml: "󰘦", yaml: "󰘦", yml: "󰘦"
        }
        return map[ext] ?? "󰈔"
    }

    function fileItem(full, isDir) {
        const name = full.replace(/\/$/, "").split("/").pop()
        return {
            glyph: fileGlyph(name, isDir),
            glyphColor: isDir ? Theme.sapphire : Theme.overlay2,
            title: name + (isDir ? "/" : ""),
            sub: tilde(full.replace(/\/$/, "")),
            badge: isDir ? "⏎ открыть   Tab войти" : "⏎ открыть   ⇧⏎ папку",
            run: shift => {
                const p = full.replace(/\/$/, "")
                Tools.open(shift && !isDir ? p.slice(0, p.lastIndexOf("/")) || "/" : p)
                Ui.closePopouts()
            },
            tab: () => setQuery(tilde(full.replace(/\/$/, "")) + (isDir ? "/" : ""))
        }
    }

    property var fdResults: []
    property string fdFor: ""
    Process {
        id: fdProc
        property string forQuery: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.fdResults = this.text.split("\n").filter(l => l !== "")
                root.fdFor = fdProc.forQuery
            }
        }
    }

    function requestFd() {
        if (arg.length < 2) {
            fdResults = []
            fdFor = arg
            return
        }
        fdProc.running = false
        fdProc.forQuery = arg
        fdProc.command = ["fd", "--ignore-case", "--fixed-strings", "--max-results", "80",
            "--color", "never", "--absolute-path", "--", arg, home]
        fdProc.running = true
    }

    function filesItems() {
        if (arg.length < 2)
            return [{ glyph: "󰈞", glyphColor: Theme.overlay1, title: "Начни вводить имя файла",
                sub: "Поиск через fd по домашней папке; ~/ или / — обзор по пути", run: () => {} }]
        return fdResults.map(p => fileItem(p, p.endsWith("/")))
    }

    // Обзор по пути: каталог до последнего "/", дальше — фильтр
    property var dirEntries: []
    property string dirFor: ""
    Process {
        id: lsProc
        property string forDir: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.dirEntries = this.text.split("\n").filter(l => l !== "" && l !== "./" && l !== "../")
                root.dirFor = lsProc.forDir
            }
        }
    }

    readonly property string pathDir: mode === "path" ? arg.slice(0, arg.lastIndexOf("/") + 1) : ""
    readonly property string pathRest: mode === "path" ? arg.slice(arg.lastIndexOf("/") + 1) : ""

    onPathDirChanged: {
        if (pathDir === "" || pathDir === dirFor) return
        lsProc.running = false
        lsProc.forDir = pathDir
        lsProc.command = ["ls", "-1Ap", "--color=never", "--", expand(pathDir)]
        lsProc.running = true
    }

    function pathItems() {
        if (dirFor !== pathDir) return []
        const rest = pathRest.toLowerCase()
        const hidden = rest.startsWith(".")
        const list = dirEntries.filter(e => hidden || !e.startsWith("."))
        const starts = list.filter(e => e.toLowerCase().startsWith(rest))
        const contains = rest === "" ? [] : list.filter(e => !e.toLowerCase().startsWith(rest) && e.toLowerCase().includes(rest))
        return [...starts, ...contains].slice(0, 200).map(e => {
            const isDir = e.endsWith("/")
            const it = fileItem(expand(pathDir) + e, isDir)
            it.ghostSource = e
            if (isDir) {
                it.run = shift => {
                    if (shift) { Tools.open(expand(pathDir) + e); Ui.closePopouts() }
                    else setQuery(pathDir + e)
                }
                it.badge = "⏎ войти   ⇧⏎ открыть"
            }
            return it
        })
    }

    // ===== Процессы =====

    property var procs: []
    Process {
        id: psProc
        command: ["ps", "-eo", "pid=,pcpu=,rss=,comm=,args=", "--sort=-pcpu"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.procs = this.text.split("\n").map(l => l.trim().match(/^(\d+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(.*)$/))
                    .filter(m => m)
                    .map(m => ({ pid: m[1], cpu: m[2], mem: Number(m[3]) / 1024, comm: m[4], args: m[5] }))
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.mode === "kill"
        triggeredOnStart: true
        onTriggered: psProc.running = true
    }

    function killItems() {
        return filterBy(procs, arg, p => [p.comm, p.args]).slice(0, 100).map(p => ({
            glyph: "󰆴",
            glyphColor: Number(p.cpu) > 50 ? Theme.red : Theme.overlay2,
            title: p.comm,
            sub: p.pid + "   ·   " + p.cpu + "% CPU   ·   " + p.mem.toFixed(0) + " МБ   ·   " + p.args,
            badge: "⏎ TERM   ⇧⏎ KILL",
            ghostSource: p.comm,
            run: shift => {
                Quickshell.execDetached(["kill", shift ? "-KILL" : "-TERM", p.pid])
                psProc.running = true
            }
        }))
    }

    // ===== Эмодзи и nerd-иконки =====

    property var glyphs: []
    FileView {
        id: glyphFile
        path: root.mode === "glyphs" || root.glyphs.length > 0 ? Quickshell.shellPath("assets/launcher/glyphs.tsv") : ""
        printErrors: false
        onLoaded: root.glyphs = text().split("\n").filter(l => l !== "").map(l => {
            const f = l.split("\t")
            return { ch: f[0], en: f[1] ?? "", ru: f[2] ?? "", kw: f[3] ?? "",
                     hay: ((f[2] ?? "") + " " + (f[3] ?? "") + " " + (f[1] ?? "")).toLowerCase() }
        })
    }

    function glyphItems() {
        const words = arg.toLowerCase().split(/\s+/).filter(w => w !== "")
        if (words.length === 0)
            return glyphs.slice(0, 120).map(glyphItem)
        const out = []
        for (const g of glyphs) {
            let s = 0
            for (const w of words) {
                const i = g.hay.indexOf(w)
                if (i < 0) { s = -1; break }
                const start = i === 0 || g.hay[i - 1] === " " || g.hay[i - 1] === "-"
                const end = i + w.length === g.hay.length || g.hay[i + w.length] === " "
                // Целое слово лучше начала слова, начало — лучше середины
                s += (start ? 2 : 1) + (start && end ? 2 : 0) + (i === 0 ? 1 : 0)
            }
            if (s > 0) out.push([s, g])
            if (out.length > 600) break
        }
        return out.sort((a, b) => b[0] - a[0]).slice(0, 120).map(x => glyphItem(x[1]))
    }

    function glyphItem(g) {
        return {
            glyph: g.ch,
            glyphSize: 22,
            title: g.ru || g.en,
            sub: g.ru ? g.en + (g.kw ? "   ·   " + g.kw : "") : "",
            badge: "⏎ копировать   ⇧⏎ ещё",
            run: shift => {
                Tools.copy(g.ch)
                if (!shift) Ui.closePopouts()
            }
        }
    }

    // ===== Итоговый список =====

    readonly property var results: {
        if (sub && sub.kind === "actions")
            return Array.from(sub.app.actions ?? []).map(a => ({
                icon: Quickshell.iconPath(a.icon || sub.app.icon, "application-x-executable"),
                title: a.name,
                sub: sub.app.name,
                run: () => launchApp(sub.app, a)
            }))
        switch (mode) {
        case "picker": return []
        case "history": return historyItems()
        case "calc": return [...calcItems(), ...calcNameItems()]
        case "vars": return varItems()
        case "shell": return shellItems()
        case "windows": return windowItems()
        case "actions": return actionItems(arg)
        case "clip": return clipItems()
        case "files": return filesItems()
        case "path": return pathItems()
        case "kill": return killItems()
        case "glyphs": return glyphItems()
        }
        // Обычный поиск: калькулятор, цвет, приложения, потом действия
        const out = [...calcItems(), ...colorItem(/^(rgb|hsl|hsv)a?\(/i.test(arg.trim()) ? arg : ""), ...appResults(arg)]
        if (arg.trim().length >= 2)
            out.push(...actionItems(arg.trim()).slice(0, 4))
        return out
    }

    readonly property var selected: results[selIdx] ?? null

    // ===== Призрачная подсказка (хвост, который допишется по →) =====

    readonly property string ghost: {
        const q = query
        if (q === "" || sub) return ""
        let full = ""
        if (mode === "shell") {
            const h = Zsh.suggest(arg)
            if (h !== "") return h.slice(arg.length)
            // Единственный кандидат дополнения — допишем слово
            const w = arg.slice(wordStart(arg))
            const c = zshFor === arg ? zshItems.filter(x => x.word.startsWith(w)) : []
            return c.length === 1 && w !== "" ? c[0].word.slice(w.length) : ""
        }
        if (mode === "calc") {
            const w = calcWord()
            if (w === "") return ""
            const n = Calc.names.find(n => n.startsWith(w) && n !== w)
            return n ? n.slice(w.length) : ""
        }
        if (mode === "path") {
            const r = pathRest
            const e = results.find(it => it.ghostSource?.toLowerCase().startsWith(r.toLowerCase()))
            return e && r !== "" ? e.ghostSource.slice(r.length) : ""
        }
        const top = results.find(it => it.ghostSource !== undefined)
        const a = arg.trim()
        if (!top || a === "" || arg !== a && mode !== "apps") return ""
        if (top.ghostSource.toLowerCase().startsWith(a.toLowerCase()) && arg.endsWith(a))
            return top.ghostSource.slice(a.length)
        return ""
    }

    function acceptGhost() {
        if (ghost === "") return false
        setQuery(query + ghost)
        return true
    }

    // ===== Ввод =====

    property bool _settingQuery: false

    function setQuery(t) {
        _settingQuery = true
        searchInput.text = t
        searchInput.cursorPosition = t.length
        _settingQuery = false
    }

    onQueryChanged: {
        confirmId = ""
        asyncTimer.restart()
        if (mode === "calc" || mode === "apps") calcTimer.restart()
    }

    onModeChanged: {
        if (mode === "clip") clipList.running = true
        if (mode === "shell") { Zsh.start(); Zsh.refreshHistory() }
    }

    onResultsChanged: if (selIdx >= results.length) selIdx = 0

    // Ввод текста сбрасывает выделение на первый пункт
    function resetSel() {
        selIdx = 0
        list.positionViewAtBeginning()
    }

    Timer {
        id: calcTimer
        interval: 60
        onTriggered: root.requestCalc()
    }

    Timer {
        id: asyncTimer
        interval: 90
        onTriggered: {
            if (root.mode === "shell") root.requestZsh()
            else if (root.mode === "files") root.requestFd()
        }
    }

    Component.onCompleted: {
        histRead.running = true
        const preset = Tools.launcherPreset
        Tools.launcherPreset = ""
        if (preset.startsWith("color:"))
            openPicker(preset.slice(6))
        else if (preset !== "")
            setQuery(preset)
        searchInput.forceActiveFocus()
    }

    // ===== История запросов =====
    // Ctrl+↑/↓ (или ↑ в пустой строке) листают историю; если что-то уже введено —
    // только запросы, начинающиеся с введённого (как up-line-or-search в zsh).
    // Ctrl+R — список истории с поиском.

    property int histPos: -1          // -1 — не листаем
    property string histDraft: ""     // что было введено до начала листания
    property bool _histSetting: false
    property bool histArrows: false   // листание начато простой ↑ — тогда и ↓ листает

    // Запрос, который сейчас выполнится — в историю
    function remember() {
        if (sub && (sub.kind === "history" || sub.kind === "picker")) return
        Tools.addQuery(query)
    }

    function histMatches() {
        return Tools.queries.filter(q => q.startsWith(histDraft) && q !== histDraft)
    }

    function histStep(d) {
        if (histPos === -1) {
            if (d > 0) return false
            histDraft = query
        }
        const list = histMatches()
        const next = histPos - d
        if (next >= list.length) return true
        histPos = Math.max(-1, next)
        _histSetting = true
        setQuery(histPos === -1 ? histDraft : list[histPos])
        _histSetting = false
        return true
    }

    function openHistory() {
        sub = { kind: "history", back: query }
        selIdx = 0
        histPos = -1
    }

    function modeIcon(q) {
        if (/^kill\s/.test(q)) return modes.kill
        const m = { "=": "calc", "$": "vars", ">": "shell", ":": "windows", "!": "actions",
                    "#": "clip", ";": "glyphs", "/": "path" }[q.charAt(0)]
        if (m) return modes[m]
        if (q.charAt(0) === "~") return q.startsWith("~/") ? modes.path : modes.files
        return Calc.looksLikeMath(q) ? modes.calc : modes.apps
    }

    function historyItems() {
        return filterBy(Tools.queries, arg, q => [q]).slice(0, 200).map(q => {
            const m = modeIcon(q)
            return {
                glyph: m.icon,
                glyphColor: m.color,
                title: q,
                badge: "⏎ в строку   ⇧⏎ выполнить   ⇧Del удалить",
                run: shift => {
                    sub = null
                    setQuery(q)
                    if (shift) Qt.callLater(() => root.runSelected(false))
                },
                del: () => Tools.removeQuery(q)
            }
        })
    }

    function runSelected(shift) {
        if (sub && sub.kind === "picker") {
            picker.activate()
            if (!shift) Ui.closePopouts()
            return
        }
        if (selected) {
            remember()
            selected.run(shift)
        }
    }

    // Tab на строке «Выполнить» — как в zsh: общий префикс кандидатов,
    // единственный — целиком, иначе встаём на первый кандидат
    function tabShell() {
        if (zshFor !== arg || zshItems.length === 0) return acceptGhost()
        const w = arg.slice(wordStart(arg))
        const words = zshItems.map(x => x.word).filter(x => x.startsWith(w))
        if (words.length === 1) { applyZsh(words[0]); return true }
        let lcp = words[0] ?? ""
        for (const x of words)
            while (!x.startsWith(lcp)) lcp = lcp.slice(0, -1)
        if (lcp.length > w.length) {
            setQuery(query + lcp.slice(w.length))
            return true
        }
        const first = results.findIndex(r => r.complete === true)
        if (first >= 0) selIdx = first
        return true
    }

    function tabSelected() {
        const it = selected
        if (mode === "shell" && selIdx === 0 && !sub) return tabShell()
        if (!it) return acceptGhost()
        if (it.tab) { it.tab(); return true }
        if (typeof it.complete === "string") { setQuery(it.complete); return true }
        return acceptGhost()
    }

    function back() {
        if (!sub) return false
        if (sub.kind === "picker" || sub.kind === "history") {
            const q = sub.back
            sub = null
            setQuery(q)
        } else {
            sub = null
        }
        selIdx = 0
        return true
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        anchors.bottomMargin: 10
        spacing: 10

        // Поиск
        Item {
            width: parent.width
            height: 36

            Text {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                horizontalAlignment: Text.AlignHCenter
                text: root.sub?.kind === "actions" ? "󰁔" : root.modeInfo.icon
                font.family: Theme.font
                font.pixelSize: 16
                color: root.modeInfo.color
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            TextInput {
                id: searchInput
                anchors.left: searchIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font
                font.pixelSize: 16
                color: Theme.text
                selectionColor: Theme.surface1
                clip: true

                onTextChanged: {
                    root.query = text
                    if (!root._histSetting)
                        root.histPos = -1
                    if (root._settingQuery) {
                        root.resetSel()
                        return
                    }
                    if (root.sub?.kind === "actions")
                        root.sub = null
                    if (root.sub?.kind === "picker") {
                        const c = Colors.parse(text)
                        if (c) picker.setColor(c)
                        return
                    }
                    root.resetSel()
                }

                Keys.onPressed: event => {
                    const shift = event.modifiers & Qt.ShiftModifier
                    const ctrl = event.modifiers & Qt.ControlModifier
                    const inPicker = root.sub?.kind === "picker"
                    const step = d => {
                        if (inPicker) picker.move(d)
                        else root.selIdx = Math.max(0, Math.min(root.selIdx + d, root.results.length - 1))
                    }
                    switch (event.key) {
                    case Qt.Key_Escape:
                        if (!root.back()) Ui.closePopouts()
                        break
                    case Qt.Key_Down:
                        if (inPicker && ctrl) picker.nudge(0, 0, -0.03)
                        else if (!root.sub && (ctrl || root.histPos >= 0 && root.histArrows)) root.histStep(1)
                        else step(1)
                        break
                    case Qt.Key_Up:
                        if (inPicker && ctrl) picker.nudge(0, 0, 0.03)
                        else if (!root.sub && ctrl) {
                            if (root.histPos === -1) root.histArrows = false
                            root.histStep(-1)
                        }
                        // Простая ↑ уходит в историю из пустой строки (как в терминале),
                        // дальше ↑↓ листают её, пока не начнёшь печатать
                        else if (!root.sub && root.selIdx === 0
                                 && (root.query === "" && root.histPos === -1 || root.histPos >= 0 && root.histArrows)) {
                            if (root.histPos === -1) root.histArrows = true
                            root.histStep(-1)
                        } else step(-1)
                        break
                    case Qt.Key_P:
                    case Qt.Key_N:
                        if (!ctrl || root.sub) { event.accepted = false; return }
                        if (root.histPos === -1) root.histArrows = false
                        root.histStep(event.key === Qt.Key_P ? -1 : 1)
                        break
                    case Qt.Key_R:
                        if (!ctrl) { event.accepted = false; return }
                        if (root.sub?.kind === "history") root.back()
                        else if (!root.sub) root.openHistory()
                        break
                    case Qt.Key_PageDown:
                        step(8)
                        break
                    case Qt.Key_PageUp:
                        step(-8)
                        break
                    case Qt.Key_Left:
                        if (inPicker && ctrl) { picker.nudge(-2 / 360, 0, 0); break }
                        if (root.sub?.kind === "actions" && searchInput.cursorPosition === 0) { root.back(); break }
                        event.accepted = false
                        return
                    case Qt.Key_Right:
                        if (inPicker && ctrl) { picker.nudge(2 / 360, 0, 0); break }
                        if (searchInput.cursorPosition === searchInput.text.length && root.acceptGhost()) break
                        event.accepted = false
                        return
                    case Qt.Key_End:
                        if (searchInput.cursorPosition === searchInput.text.length && root.acceptGhost()) break
                        event.accepted = false
                        return
                    case Qt.Key_Tab:
                        root.tabSelected()
                        break
                    case Qt.Key_Backtab:
                        root.back()
                        break
                    case Qt.Key_Delete:
                        if (shift && root.selected?.del) {
                            root.selected.del()
                            break
                        }
                        event.accepted = false
                        return
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.runSelected(shift)
                        break
                    default:
                        event.accepted = false
                        return
                    }
                    event.accepted = true
                }

                // Призрачный хвост автодополнения
                Text {
                    visible: root.ghost !== "" && searchInput.cursorPosition === searchInput.text.length
                        && searchInput.contentWidth < searchInput.width - 40
                    x: searchInput.contentWidth
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.ghost
                    font.family: Theme.font
                    font.pixelSize: 16
                    color: Theme.overlay0
                }

                Text {
                    anchors.fill: parent
                    visible: searchInput.text === ""
                    text: root.sub?.kind === "actions" ? root.sub.app.name + " — действия" : root.modeInfo.hint
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.italic: true
                    color: Theme.overlay0
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // Градиентный разделитель
        Rectangle {
            width: parent.width
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.alpha(Theme.gradStart, 0.6) }
                GradientStop { position: 1; color: Theme.alpha(Theme.gradEnd, 0.6) }
            }
        }

        Item {
            width: parent.width
            height: parent.height - 36 - 1 - 20 - 20

            ColorPicker {
                id: picker
                anchors.fill: parent
                anchors.topMargin: 6
                visible: root.sub?.kind === "picker"
                onEdited: {
                    if (root.sub?.kind === "picker")
                        root.setQuery(Colors.hex(picker.rgba))
                }
                onCopyRequested: text => Tools.copy(text)
                onPickRequested: {
                    Ui.closePopouts()
                    Tools.pickColor()
                }
            }

            ListView {
                id: list
                anchors.fill: parent
                visible: !picker.visible
                clip: true
                model: root.results
                currentIndex: root.selIdx
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 200

                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    readonly property bool selected: index === root.selIdx
                    readonly property bool big: modelData.big ?? false
                    readonly property bool hasPlot: modelData.plot !== undefined

                    width: list.width
                    height: hasPlot ? 220 : big ? 60 : 46
                    radius: 10
                    color: selected ? Theme.cardBg
                         : rma.containsMouse ? Theme.alpha(Theme.cardBg, 0.5) : "transparent"

                    // Верхняя строка (у графика под ней ещё сам график)
                    Item {
                        id: header
                        width: parent.width
                        height: row.hasPlot ? 46 : row.height
                    }

                    PlotView {
                        visible: row.hasPlot
                        anchors.top: header.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        anchors.topMargin: 0
                        plot: row.modelData.plot ?? null
                    }

                    Rectangle {
                        visible: row.selected
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: header.verticalCenter
                        width: 3
                        height: row.big ? 34 : 24
                        radius: 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.gradStart }
                            GradientStop { position: 1; color: Theme.gradEnd }
                        }
                    }

                    // Иконка: картинка приложения / образец цвета / превью из буфера / глиф
                    Item {
                        id: iconBox
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: header.verticalCenter
                        width: row.big ? 36 : 28
                        height: width

                        IconImage {
                            anchors.fill: parent
                            visible: (row.modelData.icon ?? "") !== ""
                            implicitSize: parent.width
                            source: row.modelData.icon ?? ""
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: row.modelData.swatch !== undefined
                            radius: 8
                            color: row.modelData.swatch ?? "transparent"
                            border.width: 1
                            border.color: Theme.surface1
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: (row.modelData.glyph ?? "") !== "" && !clipThumb.visible
                            text: row.modelData.glyph ?? ""
                            font.family: Theme.font
                            font.pixelSize: row.modelData.glyphSize ?? (row.big ? 22 : 18)
                            color: row.modelData.glyphColor ?? Theme.mauve
                        }

                        // Превью картинки из cliphist — декодируем лениво в кэш
                        Image {
                            id: clipThumb
                            anchors.fill: parent
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 64
                            sourceSize.height: 64
                            property string file: ""
                            source: file !== "" ? "file://" + file : ""

                            Process {
                                id: decode
                                property string target: ""
                                onExited: (code, _s) => { if (code === 0) clipThumb.file = decode.target }
                            }

                            Component.onCompleted: {
                                const line = row.modelData.clipImage ?? ""
                                if (line === "") return
                                const id = line.slice(0, line.indexOf("\t"))
                                const dir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
                                decode.target = dir + "/qs-cliphist/" + id + "." + row.modelData.clipExt
                                decode.exec(["sh", "-c",
                                    'mkdir -p "${2%/*}" && { [ -s "$2" ] || printf "%s" "$1" | cliphist decode > "$2"; }',
                                    "qs", line, decode.target])
                            }
                        }
                    }

                    Column {
                        anchors.left: iconBox.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: badge.shown ? badge.implicitWidth + 20 : 12
                        anchors.verticalCenter: header.verticalCenter
                        spacing: 1

                        GradientText {
                            visible: row.selected && !row.big
                            pixelSize: 14
                            maxChars: 56
                            text: row.modelData.title ?? ""
                        }
                        Text {
                            visible: !row.selected || row.big
                            width: parent.width
                            text: row.modelData.title ?? ""
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: row.big ? 20 : 14
                            font.weight: row.big ? Font.DemiBold : Font.Normal
                            color: Theme.text
                        }
                        Text {
                            visible: (row.modelData.sub ?? "") !== ""
                            width: parent.width
                            text: row.modelData.sub ?? ""
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: row.modelData.subColor ?? Theme.overlay1
                        }
                    }

                    Text {
                        id: badge
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: header.verticalCenter
                        readonly property bool shown: row.selected || rma.containsMouse
                        visible: shown
                        text: row.modelData.badge ?? ""
                        font.family: Theme.font
                        font.pixelSize: 10
                        color: Theme.overlay0
                    }

                    MouseArea {
                        id: rma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: event => {
                            root.selIdx = row.index
                            root.remember()
                            row.modelData.run(event.button === Qt.MiddleButton
                                || (event.modifiers & Qt.ShiftModifier))
                            searchInput.forceActiveFocus()
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: {
                if (root.sub?.kind === "picker")
                    return "↑↓ формат   ·   ⏎ копировать   ·   Ctrl+←→ оттенок   ·   Ctrl+↑↓ яркость   ·   Esc назад"
                if (root.sub?.kind === "actions")
                    return "↑↓ навигация   ·   ⏎ запуск   ·   Esc/⇧Tab назад"
                if (root.sub?.kind === "history")
                    return "⏎ в строку   ·   ⇧⏎ выполнить   ·   ⇧Del удалить   ·   Esc назад"
                if (root.histPos >= 0)
                    return "История " + (root.histPos + 1) + "/" + root.histMatches().length
                        + "   ·   " + (root.histArrows ? "↑↓" : "Ctrl+↑↓") + " листать   ·   печатай — выйти"
                const n = root.results.length
                const hints = {
                    apps: n + " результатов   ·   ⏎ запуск   ·   Tab действия   ·   ↑ / Ctrl+R история",
                    calc: root.plotData ? "⏎ открыть в gnuplot   ·   plot(f, от, до)   ·   наведи — значение"
                        : "⏎ копировать   ·   ⇧⏎ в ans   ·   x = 2+2 — переменная   ·   plot(f) — график",
                    shell: "⏎ фон   ·   ⇧⏎ терминал   ·   Tab дополнить   ·   → из истории",
                    path: "⏎ открыть / войти   ·   Tab войти   ·   → дописать",
                    files: "⏎ открыть   ·   ⇧⏎ папку   ·   Tab в путь"
                }
                return hints[root.mode] ?? (n + " результатов   ·   ↑↓ навигация   ·   ⏎ выбрать   ·   Esc закрыть")
            }
            font.family: Theme.font
            font.pixelSize: 10
            color: Theme.overlay0
        }
    }
}
