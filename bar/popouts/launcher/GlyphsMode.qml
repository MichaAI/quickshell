import QtQuick
import Quickshell
import Quickshell.Io
import "../../../services"

// «;» — эмодзи и nerd-иконки по-русски и по-английски, Enter копирует
Item {
    id: mode

    required property var launcher

    property var glyphs: []

    // Таблица большая — читаем, только когда режим впервые понадобился
    FileView {
        path: mode.launcher.mode === "glyphs" || mode.glyphs.length > 0
            ? Quickshell.shellPath("assets/launcher/glyphs.tsv") : ""
        printErrors: false
        onLoaded: mode.glyphs = text().split("\n").filter(l => l !== "").map(l => {
            const f = l.split("\t")
            return { ch: f[0], en: f[1] ?? "", ru: f[2] ?? "", kw: f[3] ?? "",
                     hay: ((f[2] ?? "") + " " + (f[3] ?? "") + " " + (f[1] ?? "")).toLowerCase() }
        })
    }

    function items() {
        const words = launcher.arg.toLowerCase().split(/\s+/).filter(w => w !== "")
        if (words.length === 0)
            return glyphs.slice(0, 120).map(item)
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
        return out.sort((a, b) => b[0] - a[0]).slice(0, 120).map(x => item(x[1]))
    }

    function item(g) {
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
}
