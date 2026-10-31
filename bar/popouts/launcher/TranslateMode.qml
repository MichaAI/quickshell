import QtQuick
import "../../../config"
import "../../../services"

// «tr текст» — перевод через Google Translate (без ключа). Язык исходника
// определяется сам: с первого из Settings.translateLangs — на второй,
// с остальных — на первый. «tr de: текст» — на конкретный язык.
// ⏎ копирует, ⇧⏎ переводит перевод обратно. Пустой запрос — недавние.
Item {
    id: mode

    required property var launcher

    readonly property var langs: Settings.translateLangs
    readonly property var parsed: {
        const m = launcher.arg.match(/^\s*([a-z]{2,3}(?:-[A-Za-z]{2,4})?):\s*([\s\S]*)$/)
        return m ? { to: m[1], text: m[2].trim() } : { to: "", text: launcher.arg.trim() }
    }
    // {key, text, to, from, result, dict: [{pos, terms: [{word, back}]}], error}
    readonly property var last: LauncherState.cache.tr ?? null
    property int token: 0

    function keyOf(p) {
        return p.to + "\n" + p.text
    }

    function request() {
        const p = parsed
        if (p.text === "" || last?.key === keyOf(p)) return
        const t = ++token
        fetch(p.text, p.to || langs[0], (code, j) => {
            if (t !== mode.token) return
            if (!j) return mode.fail(p, code)
            // Исходник и так на первом языке — значит, нужен второй
            if (!p.to && j[2] === langs[0] && langs.length > 1)
                fetch(p.text, langs[1], (code2, j2) => {
                    if (t !== mode.token) return
                    if (!j2) return mode.fail(p, code2)
                    mode.store(p, langs[1], j2)
                })
            else
                mode.store(p, p.to || langs[0], j)
        })
    }

    function fetch(text, to, done) {
        const url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl="
            + encodeURIComponent(to) + "&dt=t&dt=bd&q=" + encodeURIComponent(text)
        Tools.run(Tools.curl([url]), (code, out) => {
            if (!mode) return
            let j = null
            if (code === 0) try { j = JSON.parse(out) } catch (e) {}
            done(code, j)
        })
    }

    function fail(p, code) {
        LauncherState.put("tr", { key: keyOf(p), text: p.text, error: code === 127 ? "curl не найден"
            : "Не получилось: curl вернул " + code })
    }

    function store(p, to, j) {
        LauncherState.put("tr", {
            key: keyOf(p), text: p.text, to, from: j[2] ?? "?", error: "",
            result: (j[0] ?? []).map(s => s[0] ?? "").join(""),
            dict: (j[1] ?? []).map(d => ({
                pos: d[0],
                terms: (d[2] ?? []).slice(0, 6).map(e => ({ word: e[0], back: (e[1] ?? []).slice(0, 4).join(", ") }))
            }))
        })
    }

    // Ctrl+⏎: текст — в Google Translate в браузере
    function handoff() {
        const p = parsed
        if (p.text === "") return null
        const to = last?.key === keyOf(p) ? last.to : p.to || langs[0]
        return {
            app: "Google Translate",
            run: () => Tools.open("https://translate.google.com/?sl=auto&tl=" + to + "&op=translate&text="
                + encodeURIComponent(p.text))
        }
    }

    function copyItem(word, sub, glyph) {
        return {
            glyph, glyphColor: Theme.teal, title: word, sub, badge: "⏎ копировать",
            run: () => { Tools.copy(word); Ui.closePopouts() }
        }
    }

    function items() {
        const p = parsed
        if (p.text === "") {
            const r = LauncherState.recentOf("tr")
            if (r.length === 0)
                return [{ glyph: "󰗊", glyphColor: Theme.overlay1, title: "Что перевести?",
                          sub: "tr hello world   ·   tr de: доброе утро   ·   " + langs.join(" ⇄ "), run: () => {} }]
            return r.map(x => ({
                glyph: "󰋚", glyphColor: Theme.overlay1,
                title: x.result, sub: x.text + "   ·   " + x.from + " → " + x.to,
                badge: "⏎ копировать   ⇧⏎ в строку   ⇧Del забыть",
                run: shift => {
                    if (shift) launcher.setQuery("tr " + (x.forced ? x.to + ": " : "") + x.text)
                    else { Tools.copy(x.result); Ui.closePopouts() }
                },
                del: () => LauncherState.forget("tr", y => y.text === x.text && y.to === x.to)
            }))
        }
        const l = last
        if (!l || l.key !== keyOf(p))
            return [{ glyph: "󰔟", glyphColor: Theme.overlay1, title: "Перевожу…", sub: p.text, progress: -1, run: () => {} }]
        if (l.error)
            return [{ glyph: "󰗊", glyphColor: Theme.red, title: l.error, sub: p.text, run: () => {} }]
        const out = [{
            big: true,
            glyph: "󰗊",
            glyphColor: Theme.teal,
            title: l.result,
            sub: l.from + " → " + l.to,
            badge: "⏎ копировать   ⇧⏎ обратно",
            run: shift => {
                LauncherState.remember("tr", { text: l.text, result: l.result, from: l.from, to: l.to, forced: p.to !== "" },
                    x => x.to + "\n" + x.text)
                if (shift) launcher.setQuery("tr " + (l.from !== "?" && l.from !== "auto" ? l.from + ": " : "") + l.result)
                else { Tools.copy(l.result); Ui.closePopouts() }
            }
        }]
        for (const d of l.dict)
            for (const t of d.terms)
                out.push(copyItem(t.word, d.pos + (t.back ? "   ·   " + t.back : ""), "󰂺"))
        return out
    }
}
