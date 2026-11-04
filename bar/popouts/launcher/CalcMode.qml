import QtQuick
import "../../../config"
import "../../../services"
import "Match.js" as Match

// «=» — калькулятор (qalc), «$» — его переменные. Выражение в обычном
// поиске тоже считается, если похоже на математику.
Item {
    id: mode

    required property var launcher

    property var calc: ({ input: "", value: "", exact: "", assign: "" })
    property int token: 0
    property var plotData: null

    function expr() {
        const a = launcher.arg
        if (launcher.mode === "calc") return a.trim()
        if (launcher.mode === "apps" && Calc.looksLikeMath(a)) return a.trim()
        return ""
    }

    // Ctrl+⏎: выражение — в полноценный Qalculate
    function handoff() {
        const e = expr()
        if (e === "") return null
        for (const app of ["qalculate-gtk", "qalculate-qt"])
            if (LauncherState.has(app))
                return { app: "Qalculate!", run: () => Tools.launch([app, e]) }
        return { app: "qalc в терминале", run: () => Zsh.runInTerminal("qalc -i " + Zsh._quote(e)) }
    }

    function schedule() {
        timer.restart()
    }

    Timer {
        id: timer
        interval: 60
        onTriggered: mode.request()
    }

    function request() {
        const e = expr()
        if (e === "") {
            calc = { input: "", value: "", exact: "", assign: "" }
            plotData = null
            return
        }
        // plot(…) — рисуем сами, без отдельного окна gnuplot
        if (/^plot\s*\(/i.test(e)) {
            calc = { input: "", value: "", exact: "", assign: "" }
            const t = ++token
            Calc.plot(e, d => {
                if (t !== mode.token) return
                mode.plotData = d ? Object.assign({ input: e }, d) : null
            })
            return
        }
        plotData = null
        const asg = Calc.parseAssign(e)
        const ex = asg ? asg.expr : e
        const t = ++token
        Calc.evaluate(ex, res => {
            if (t !== mode.token) return
            // Пустой ответ или «эхо» без вычисления — не показываем в общем поиске
            const same = res.replace(/\s/g, "") === ex.replace(/\s/g, "")
            mode.calc = {
                input: e,
                value: (launcher.mode === "apps" && same) ? "" : res,
                exact: "",
                assign: asg ? asg.name : ""
            }
        })
        // Точный ответ — вторым запросом, тем же токеном
        if (!asg)
            Calc.evaluate(ex, res => {
                if (t !== mode.token || mode.calc.input !== e) return
                mode.calc = Object.assign({}, mode.calc, { exact: res })
            }, true)
    }

    // Заголовок графика: title из опций, иначе линии через «·»
    function plotTitle(p) {
        if (p.opts.title) return p.opts.title
        const main = p.series.filter(s => !s.im)
        const y = p.opts.style === "polar" ? "r = " : "y = "
        if (main.length === 1) return main[0].data ? main[0].label : y + main[0].label
        return main.map(s => s.label).join("   ·   ")
    }

    // Несколько линий — их имена цветами линий: это и есть легенда, полосы
    // под графиком нет. Цвета — как PlotView.seriesColor. Со своим title
    // и в mono цветом не различить — там легенда остаётся в углу графика
    function plotTitleRich(p) {
        const main = p.series.filter(s => !s.im)
        if (main.length < 2 || p.opts.title || p.opts.mono) return ""
        const esc = t => String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const color = i => i === 0 ? Theme.gradStart : Theme.series[(i - 1) % Theme.series.length]
        return main.map((s, i) => "<font color='" + color(i) + "'>" + esc(s.label) + "</font>")
            .join("<font color='" + Theme.overlay0 + "'>   ·   </font>")
    }

    function plural(n, one, few, many) {
        const a = n % 10, b = n % 100
        return a === 1 && b !== 11 ? one : a >= 2 && a <= 4 && (b < 12 || b > 14) ? few : many
    }

    function plotSub(p) {
        const v = p.opts.style === "polar" ? "θ" : p.opts.variable
        const parts = []
        if (p.series.some(s => s.fn)) parts.push(v + " от " + Calc.fmtNum(p.min) + " до " + Calc.fmtNum(p.max))
        const pts = p.series.filter(s => s.data).reduce((a, s) => a + s.ys.length, 0)
        if (pts > 0) parts.push(pts + " " + plural(pts, "точка", "точки", "точек"))
        const lines = p.series.filter(s => !s.im).length
        if (lines > 1) parts.push(lines + " " + plural(lines, "линия", "линии", "линий"))
        return parts.join("   ·   ")
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

    function items() {
        const out = []
        if (plotData && plotData.input === expr())
            out.push({
                plot: plotData,
                glyph: "󰄧",
                title: plotTitle(plotData),
                titleRich: plotTitleRich(plotData),
                sub: plotSub(plotData),
                badge: "⏎ открыть в gnuplot",
                run: () => {
                    Tools.launch(["qalc", plotData.input])
                    Ui.closePopouts()
                }
            })
        if (calc.value !== "" && calc.input === expr()) {
            const asg = calc.assign
            out.push({
                big: true,
                glyph: asg ? "󰫧" : "󰃬",
                glyphColor: Theme.peach,
                title: asg ? asg + " = " + calc.value : calc.value,
                handoff: mode.handoff(),
                sub: asg ? "⏎ сохранить переменную" : calc.input,
                badge: asg ? "" : "⏎ копировать   ⇧⏎ в ans",
                run: shift => {
                    if (asg) {
                        Calc.setVar(asg, calc.value)
                        launcher.setQuery("$")
                    } else if (shift) {
                        Calc.setAns(calc.value)
                        launcher.setQuery("=ans")
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
    function word() {
        const m = launcher.arg.match(/[a-zA-Z_][a-zA-Z0-9_]*$/)
        return m ? m[0] : ""
    }

    function nameItems() {
        const w = word()
        if (w === "") return []
        const q = launcher.query
        return Calc.names
            .filter(n => n.toLowerCase().startsWith(w.toLowerCase()) && n !== w)
            .slice(0, 30)
            .map(n => ({
                glyph: n.endsWith("(") ? "󰊕" : Calc.vars[n] !== undefined || n === "ans" ? "󰫧" : "󰎠",
                title: n,
                sub: Calc.vars[n] !== undefined ? "= " + Calc.vars[n]
                   : n === "ans" ? "= " + (Calc.ans || "—") : "",
                badge: "Tab",
                complete: q.slice(0, q.length - w.length) + n,
                run: () => launcher.setQuery(q.slice(0, q.length - w.length) + n)
            }))
    }

    function varItems() {
        const all = Object.keys(Calc.vars).map(k => [k, Calc.vars[k]])
        if (Calc.ans !== "") all.unshift(["ans", Calc.ans])
        return Match.filterBy(all, launcher.arg, x => [x[0]]).map(x => ({
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

    function ghost() {
        const w = word()
        if (w === "") return ""
        const n = Calc.names.find(n => n.startsWith(w) && n !== w)
        return n ? n.slice(w.length) : ""
    }
}
