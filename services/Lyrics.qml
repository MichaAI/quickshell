pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Тексты песен с LRCLIB (lrclib.net, бесплатно и без ключа) для того, что
// играет сейчас (Players.active). Синхронный текст — строки со временем,
// иначе просто текст. Запрос — curl (через прокси погоды, если он задан);
// найденное запоминается на сессию.
Singleton {
    id: root

    readonly property var player: Players.active
    readonly property string key: player
        ? [player.trackArtist, player.trackTitle, player.trackAlbum, Math.round(player.length || 0)].join("\u0001")
        : ""

    // [{ t: секунды или -1, text }]
    property var lines: []
    property bool synced: false
    property bool loading: false
    readonly property bool available: lines.length > 0
    // Весь текст — для копирования
    readonly property string plain: lines.map(l => l.text).join("\n")

    property var cache: ({})

    // Индекс строки, которая звучит в момент pos (секунды); -1 — ещё ни одной
    function lineAt(pos) {
        if (!synced)
            return -1
        let lo = 0, hi = lines.length - 1, at = -1
        while (lo <= hi) {
            const mid = (lo + hi) >> 1
            if (lines[mid].t <= pos) { at = mid; lo = mid + 1 } else hi = mid - 1
        }
        return at
    }

    // "[01:23.45] текст" → строки; пустые строки-паузы оставляем: это
    // проигрыши, на них подсветка уходит с прошлой строки
    function parse(r) {
        if (!r || r.instrumental)
            return { lines: [], synced: false }
        if (r.syncedLyrics) {
            const out = []
            for (const row of r.syncedLyrics.split("\n")) {
                const m = row.match(/^\[(\d+):(\d+(?:\.\d+)?)\]\s?(.*)$/)
                if (m)
                    out.push({ t: Number(m[1]) * 60 + Number(m[2]), text: m[3].trim() })
            }
            // Мусорные записи на пару строк не считаем текстом
            if (out.filter(l => l.text !== "").length >= 3)
                return { lines: out.sort((a, b) => a.t - b.t), synced: true }
        }
        if (r.plainLyrics) {
            const out = r.plainLyrics.split("\n").map(s => ({ t: -1, text: s.trim() }))
            if (out.filter(l => l.text !== "").length >= 3)
                return { lines: out, synced: false }
        }
        return { lines: [], synced: false }
    }

    function show(res) {
        lines = res.lines
        synced = res.synced
        loading = false
    }

    onKeyChanged: {
        show({ lines: [], synced: false })
        debounce.restart()
    }

    // Трек переключают пачкой — ждём, пока метаданные устоятся
    Timer {
        id: debounce
        interval: 400
        onTriggered: root.fetch()
    }

    function fetch() {
        const k = key, p = player
        if (!p || !p.trackTitle)
            return
        if (cache[k]) {
            show(cache[k])
            return
        }
        loading = true
        const q = s => encodeURIComponent(s ?? "")
        const len = Math.round(p.length || 0)
        const base = "https://lrclib.net/api/"
        let url = base + "get?track_name=" + q(p.trackTitle) + "&artist_name=" + q(p.trackArtist)
        if (p.trackAlbum)
            url += "&album_name=" + q(p.trackAlbum)
        if (len > 0)
            url += "&duration=" + len
        get(url, r => {
            if (k !== root.key)
                return
            const res = parse(r)
            if (res.lines.length > 0 || r?.instrumental) {
                root.cache[k] = res
                root.show(res)
                return
            }
            // Точного совпадения нет — поиск, и из найденного ближайшее по длине
            get(base + "search?track_name=" + q(p.trackTitle) + "&artist_name=" + q(p.trackArtist), list => {
                if (k !== root.key)
                    return
                let best = { lines: [], synced: false }
                const cands = (Array.isArray(list) ? list : [])
                    .filter(x => len <= 0 || Math.abs((x.duration ?? 0) - len) <= 3)
                for (const x of cands) {
                    const res2 = parse(x)
                    if (res2.lines.length > 0 && (best.lines.length === 0 || (res2.synced && !best.synced)))
                        best = res2
                }
                root.cache[k] = best
                root.show(best)
            })
        })
    }

    Component {
        id: fetcher
        Process {
            id: req
            property var done
            stdout: StdioCollector {
                onStreamFinished: {
                    let r = null
                    try {
                        r = JSON.parse(text)
                    } catch (e) {}
                    req.done(r)
                    req.destroy()
                }
            }
        }
    }

    function get(url, done) {
        const cmd = ["curl", "-sfL", "-m", "15", "-A", "quickshell-lyrics github.com/MichaAI/quickshell"]
        if (Weather.proxy !== "")
            cmd.push("-x", Weather.proxy)
        cmd.push(url)
        const p = fetcher.createObject(root, { command: cmd, done: done })
        p.running = true
    }
}
