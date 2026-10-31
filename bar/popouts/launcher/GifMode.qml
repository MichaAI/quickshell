import QtQuick
import Quickshell
import "../../../config"
import "../../../services"

// «gif …» — поиск гифок в Klipy или GIPHY (Tenor закрыл API летом 2026).
// ⏎ копирует ссылку, ⇧⏎ — саму гифку (image/gif, вставляется в мессенджеры).
// Пустой запрос — недавние; результаты запроса помнятся до следующего.
// Ключ: «gif key <ключ>» сохраняет его в файл (LauncherState.keysDir),
// ещё — QS_GIF_KEY_FILE (секрет sops/agenix), QS_GIF_KEY, Settings.gifKey.
Item {
    id: mode

    required property var launcher

    readonly property string provider: Settings.gifProvider
    readonly property string providerName: provider === "giphy" ? "GIPHY" : "Klipy"
    readonly property string signup: provider === "giphy" ? "developers.giphy.com" : "partner.klipy.com"

    // Откуда ключ — первое непустое
    readonly property var keySource: {
        const k = LauncherState.keys
        const env = Quickshell.env("QS_GIF_KEY") ?? ""
        if (Settings.gifKey) return { key: Settings.gifKey, from: "Settings.gifKey" }
        if (env) return { key: env, from: "переменная QS_GIF_KEY" }
        if (k.gif) return { key: k.gif, from: LauncherState.keyFiles.gif }
        if (k[provider]) return { key: k[provider], from: LauncherState.keyFiles[provider], own: true }
        return { key: "", from: "" }
    }
    readonly property string key: keySource.key

    function tilde(p) {
        const h = Quickshell.env("HOME")
        return p.startsWith(h + "/") ? "~" + p.slice(h.length) : p
    }
    // «gif key …» — ввод ключа, не поиск
    readonly property bool keyView: /^key(\s|$)/.test(launcher.arg)

    // {q, list: [{id, title, thumb, url, w, h}]} — последний ответ
    readonly property var last: LauncherState.cache.gif ?? null
    property string error: ""
    property bool loading: false
    property int token: 0

    function request() {
        const q = launcher.arg.trim()
        error = ""
        if (q === "" || key === "" || keyView || last?.q === q) {
            loading = false
            return
        }
        const t = ++token
        loading = true
        const e = encodeURIComponent(q)
        const url = provider === "giphy"
            ? `https://api.giphy.com/v1/gifs/search?api_key=${key}&q=${e}&limit=30&rating=pg-13`
            : `https://api.klipy.com/api/v1/${key}/gifs/search?q=${e}&per_page=30&customer_id=${LauncherState.clientId}&content_filter=medium`
        Tools.run(Tools.curl([url]), (code, out) => {
            if (!mode) return
            if (t !== mode.token) return
            mode.loading = false
            if (code !== 0) {
                mode.error = code === 127 ? "curl не найден" : "Сеть или ключ: curl вернул " + code
                return
            }
            try {
                LauncherState.put("gif", { q, list: mode.parse(JSON.parse(out)) })
            } catch (err) {
                mode.error = "Непонятный ответ: " + err
            }
        })
    }

    function parse(j) {
        if (provider === "giphy")
            return (j.data ?? []).map(g => ({
                id: g.id,
                title: g.title || g.slug || "",
                thumb: g.images?.fixed_height_small?.url ?? g.images?.preview_gif?.url ?? "",
                url: g.images?.original?.url ?? g.url,
                page: g.url ?? "",
                w: Number(g.images?.original?.width ?? 0),
                h: Number(g.images?.original?.height ?? 0)
            }))
        return (j.data?.data ?? []).filter(g => g.file).map(g => ({
            id: g.slug ?? String(g.id),
            title: g.title ?? "",
            thumb: g.file.sm?.gif?.url ?? g.file.xs?.gif?.url ?? "",
            url: g.file.hd?.gif?.url ?? g.file.md?.gif?.url ?? "",
            page: g.slug ? "https://klipy.com/gifs/" + g.slug : "",
            w: g.file.hd?.gif?.width ?? 0,
            h: g.file.hd?.gif?.height ?? 0
        }))
    }

    function item(g, recent) {
        return {
            thumbUrl: g.thumb,
            glyph: "󰵸",
            glyphColor: Theme.overlay1,
            title: g.title || "GIF",
            sub: (g.w ? g.w + "×" + g.h + "   ·   " : "") + (recent ? "недавняя" : provider),
            badge: "⏎ ссылка   ⇧⏎ гифка" + (recent ? "   ⇧Del забыть" : ""),
            handoff: { app: "браузер", run: () => Tools.open(g.page || g.url) },
            run: shift => {
                LauncherState.remember("gif", g, x => x.url)
                if (shift) {
                    const f = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-gif/full-" + Qt.md5(g.url) + ".gif"
                    Tools.download(g.url, f, "GIF: " + (g.title || "гифка"), "Гифка в буфере обмена",
                        file => Tools.launch(["sh", "-c", 'wl-copy --type image/gif < "$1"', "qs", file], "wl-copy"))
                } else
                    Tools.copy(g.url)
                Ui.closePopouts()
            },
            del: recent ? () => LauncherState.forget("gif", x => x.url === g.url) : undefined
        }
    }

    function note(title, sub) {
        return { glyph: "󰵸", glyphColor: Theme.overlay1, title, sub, run: () => {} }
    }

    function keyItems() {
        const v = launcher.arg.slice(3).trim()
        if (v !== "")
            return [{
                glyph: "󰌆", glyphColor: Theme.green,
                title: "Сохранить ключ " + providerName,
                sub: "В " + tilde(LauncherState.keyFiles[provider]) + " (только для тебя), не в историю",
                badge: "⏎ сохранить",
                noHistory: true,
                run: () => {
                    LauncherState.saveKey(provider, v)
                    launcher.setQuery("gif ")
                }
            }]
        const s = keySource
        if (s.key === "")
            return [note("Вставь ключ " + providerName + " после «gif key »", "Бесплатно на " + signup
                + "   ·   ляжет в " + tilde(LauncherState.keyFiles[provider]))]
        return [{
            glyph: "󰌆", glyphColor: Theme.green,
            title: "Ключ " + providerName + ": …" + s.key.slice(-4),
            sub: "Из " + tilde(s.from) + (s.own ? "" : "   ·   поменять — там же"),
            badge: s.own ? "⇧Del удалить" : "",
            run: () => {},
            del: s.own ? () => LauncherState.deleteKey(provider) : undefined
        }]
    }

    function items() {
        const q = launcher.arg.trim()
        if (keyView) return keyItems()
        if (key === "")
            return [
                {
                    glyph: "󰌆", glyphColor: Theme.yellow,
                    title: "Нужен ключ " + providerName,
                    sub: "⏎ — вставить его сюда   ·   бесплатно на " + signup,
                    run: () => launcher.setQuery("gif key ")
                },
                {
                    glyph: "󰖟", glyphColor: Theme.blue,
                    title: q === "" ? "Открыть GIPHY в браузере" : "Искать «" + q + "» на GIPHY в браузере",
                    run: () => { Tools.open("https://giphy.com/search/" + encodeURIComponent(q)); Ui.closePopouts() }
                }
            ]
        if (q === "") {
            const r = LauncherState.recentOf("gif")
            return r.length ? r.map(g => item(g, true)) : [note("Что ищем?", "gif кот, gif thumbs up…")]
        }
        if (error !== "") return [note(error, "")]
        if (last?.q === q) return last.list.length ? last.list.map(g => item(g, false)) : [note("Ничего не нашлось", q)]
        return [Object.assign(note("Ищу…", q), { progress: -1 })]
    }
}
