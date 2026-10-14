import QtQuick
import "../../../config"
import "../../../services"

// «>» — команда zsh: запуск в фоне или в терминале, дополнение
// через настоящий zsh, история команд
Item {
    id: mode

    required property var launcher

    property var zshItems: []
    property string zshFor: ""
    property int token: 0

    function request() {
        const cmd = launcher.arg
        if (cmd.trim() === "") {
            zshItems = []
            zshFor = ""
            return
        }
        const t = ++token
        Zsh.complete(cmd, items => {
            if (t !== mode.token) return
            mode.zshItems = items
            mode.zshFor = cmd
        })
    }

    // Начало текущего (последнего) слова команды
    function wordStart(cmd) {
        let i = cmd.length
        while (i > 0 && !(cmd[i - 1] === " " && cmd[i - 2] !== "\\"))
            i--
        return i
    }

    function apply(word) {
        const cmd = launcher.arg
        const q = launcher.query
        const prefix = q.slice(0, q.length - cmd.length)
        const head = cmd.slice(0, wordStart(cmd))
        launcher.setQuery(prefix + head + word + (word.endsWith("/") || word.endsWith("=") ? "" : " "))
    }

    function runCmd(cmd, inTerminal) {
        if (inTerminal)
            Zsh.runInTerminal(cmd)
        else
            Zsh.run(cmd)
        Ui.closePopouts()
    }

    function items() {
        const cmd = launcher.arg
        const out = []
        if (cmd.trim() !== "")
            out.push({
                glyph: "󰆍",
                glyphColor: Theme.green,
                title: cmd,
                sub: "Выполнить в фоне — вывод придёт уведомлением",
                badge: "⏎ фон   ⇧⏎ терминал",
                run: shift => runCmd(cmd, shift)
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
                    run: () => apply(c.word),
                    tab: () => apply(c.word)
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
                run: shift => runCmd(h.replace(/\\n/g, "\n"), shift)
            })
        }
        return out
    }

    // Tab на строке «Выполнить» — как в zsh: общий префикс кандидатов,
    // единственный — целиком, иначе встаём на первый кандидат
    function tab() {
        const arg = launcher.arg
        if (zshFor !== arg || zshItems.length === 0) return launcher.acceptGhost()
        const w = arg.slice(wordStart(arg))
        const words = zshItems.map(x => x.word).filter(x => x.startsWith(w))
        if (words.length === 1) { apply(words[0]); return true }
        let lcp = words[0] ?? ""
        for (const x of words)
            while (!x.startsWith(lcp)) lcp = lcp.slice(0, -1)
        if (lcp.length > w.length) {
            launcher.setQuery(launcher.query + lcp.slice(w.length))
            return true
        }
        const first = launcher.results.findIndex(r => r.complete === true)
        if (first >= 0) launcher.selIdx = first
        return true
    }

    function ghost() {
        const arg = launcher.arg
        const h = Zsh.suggest(arg)
        if (h !== "") return h.slice(arg.length)
        // Единственный кандидат дополнения — допишем слово
        const w = arg.slice(wordStart(arg))
        const c = zshFor === arg ? zshItems.filter(x => x.word.startsWith(w)) : []
        return c.length === 1 && w !== "" ? c[0].word.slice(w.length) : ""
    }
}
