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
                title: "y = " + plotData.f,
                sub: "x от " + plotData.min + " до " + plotData.max,
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
