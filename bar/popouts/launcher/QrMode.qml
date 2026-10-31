import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../../components"

// «qr …» — QR-код из текста. qrencode даёт только матрицу, рисует её
// QrView в стиле шелла; ⏎ копирует ровно эту картинку (скрытый QrView
// побольше сохраняет её в PNG), ⇧⏎ открывает. Пустой запрос — из буфера
// обмена; ниже — недавние коды.
Item {
    id: mode

    required property var launcher

    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-qr"
    property string clipText: ""
    // text -> матрица ["0101…", …]
    readonly property var made: LauncherState.cache.qr ?? ({})
    property string error: ""

    readonly property string text: launcher.arg !== "" ? launcher.arg : clipText

    function fileFor(t) {
        return dir + "/" + Qt.md5(t) + ".png"
    }

    function refreshClip() {
        Tools.run(["wl-paste", "--no-newline", "--type", "text"], (code, out) => {
            if (!mode) return
            mode.clipText = code === 0 ? out.slice(0, 2000) : ""
            mode.request()
        })
    }

    function request() {
        const t = text
        error = ""
        if (t === "" || made[t]) return
        Tools.run(["sh", "-c", 'printf "%s" "$1" | qrencode -t ASCII -m 0 -o -', "qs", t],
            (code, out, err) => {
                if (!mode) return
                if (code !== 0) {
                    if (t === mode.text)
                        mode.error = code === 127 ? "qrencode не найден" : err.trim() || "qrencode: код " + code
                    return
                }
                const m = Object.assign({}, mode.made)
                m[t] = out.split("\n").filter(l => l !== "")
                    .map(l => (l.match(/../g) ?? []).map(p => p === "##" ? "1" : "0").join(""))
                LauncherState.put("qr", m)
            })
    }

    // Картинка в файл: скрытый QrView рисует матрицу и сохраняет PNG
    QrView {
        id: exporter
        width: 720
        height: 720
        opacity: 0
        property var pending: null
        onPainted: {
            const p = pending
            if (!p || matrix !== p.matrix) return
            pending = null
            p.done(save(p.file) ? p.file : "")
        }
    }

    Component.onCompleted: Tools.run(["mkdir", "-p", dir])

    function exportPng(t, done) {
        const m = made[t]
        if (!m) return
        exporter.pending = { matrix: m, file: fileFor(t), done }
        if (exporter.matrix === m) exporter.requestPaint()
        else exporter.matrix = m
    }

    // Сохранить и отдать дальше; лончер закрываем, только когда файл готов
    function withPng(t, fn) {
        exportPng(t, f => {
            if (f !== "") fn(f)
            else Zsh.notify("normal", "QR", "Не удалось сохранить картинку")
            Ui.closePopouts()
        })
    }

    function items() {
        const t = text
        const out = []
        if (t === "")
            out.push({ glyph: "󰐲", glyphColor: Theme.overlay1, title: "Текст или ссылка для QR",
                       sub: "Пустой запрос — из буфера обмена", run: () => {} })
        else if (error !== "")
            out.push({ glyph: "󰐲", glyphColor: Theme.red, title: error, sub: t, run: () => {} })
        else
            out.push({
                glyph: "󰐲",
                glyphColor: Theme.text,
                qr: made[t] ?? null,
                title: t.replace(/\s+/g, " "),
                sub: (launcher.arg === "" ? "из буфера   ·   " : "") + t.length + " симв.",
                badge: "⏎ копировать   ⇧⏎ открыть",
                handoff: made[t] ? { app: "просмотрщик", keepOpen: true, run: () => withPng(t, f => Tools.open(f)) } : undefined,
                run: shift => {
                    if (!made[t]) return
                    LauncherState.remember("qr", t, x => x)
                    withPng(t, f => {
                        if (shift) Tools.open(f)
                        else Tools.launch(["sh", "-c", 'wl-copy --type image/png < "$1"', "qs", f], "wl-copy")
                    })
                }
            })
        for (const r of LauncherState.recentOf("qr")) {
            if (r === t) continue
            out.push({
                glyph: "󰋚",
                glyphColor: Theme.overlay1,
                title: r.replace(/\s+/g, " "),
                sub: "недавний",
                badge: "⏎ показать   ⇧Del забыть",
                run: () => launcher.setQuery("qr " + r),
                del: () => LauncherState.forget("qr", x => x === r)
            })
        }
        return out
    }
}
