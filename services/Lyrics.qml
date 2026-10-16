pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Тексты песен с LRCLIB (lrclib.net, бесплатно и без ключа) для того, что
// играет сейчас (Players.active). Синхронный текст — строки со временем,
// иначе просто текст. Запрос — curl (через прокси погоды, если он задан);
// ответ сервера (есть текст или точно нет) запоминается на сессию, а сбой
// (сеть, «сервер занят») — нет: тот же трек переспрашиваем чуть позже.
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

    // Сервис создаётся при первом обращении — трек к этому времени уже
    // может играть, и смены key для него не будет
    Component.onCompleted: debounce.restart()

    onKeyChanged: {
        show({ lines: [], synced: false })
        retry.stop()
        tries = 0
        debounce.restart()
    }

    // Сбой — ещё раз через 15 с, минуту, три; дальше до смены трека не мучаем
    property int tries: 0
    function fail() {
        loading = false
        if (tries >= 3)
            return
        retry.interval = [15000, 60000, 180000][tries++]
        retry.restart()
    }
    Timer {
        id: retry
        onTriggered: root.fetch()
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
        get(url, (r, ok) => {
            if (k !== root.key)
                return
            // Точный запрос LRCLIB тяжёлый и под нагрузкой сбоит первым —
            // тогда всё равно ищем, а если и поиск пуст, не запоминаем
            const shaky = !ok
            const res = parse(r)
            if (res.lines.length > 0 || r?.instrumental) {
                root.cache[k] = res
                root.show(res)
                return
            }
            // Точного совпадения нет — поиск. Яндекс пишет всех исполнителей
            // через запятую и «(prod. …)» в названии, а в LRCLIB трек часто
            // записан только на главного — тогда ищем ещё раз попроще
            const title = root.cleanTitle(p.trackTitle), artist = root.firstArtist(p.trackArtist)
            const attempts = [[p.trackTitle, p.trackArtist]]
            if (title !== p.trackTitle || artist !== p.trackArtist)
                attempts.push([title, artist])
            const next = i => {
                get(base + "search?track_name=" + q(attempts[i][0]) + "&artist_name=" + q(attempts[i][1]), (list, ok2) => {
                    if (k !== root.key)
                        return
                    if (!ok2)
                        return root.fail()
                    const best = root.pick(list, len)
                    if (best.lines.length === 0 && i + 1 < attempts.length)
                        return next(i + 1)
                    if (best.lines.length === 0 && shaky)
                        return root.fail()
                    root.cache[k] = best
                    root.show(best)
                })
            }
            next(0)
        })
    }

    // Из найденного — ближайшее по длине (±3 с), синхронное лучше простого
    function pick(list, len) {
        let best = { lines: [], synced: false }
        const cands = (Array.isArray(list) ? list : [])
            .filter(x => len <= 0 || Math.abs((x.duration ?? 0) - len) <= 3)
        for (const x of cands) {
            const res = parse(x)
            if (res.lines.length > 0 && (best.lines.length === 0 || (res.synced && !best.synced)))
                best = res
        }
        return best
    }

    // «A, B & C feat. D» → «A»
    function firstArtist(a) {
        return (a ?? "").split(/,\s*|\s+&\s+|\s+(?:feat|ft)\.?\s+/i)[0].trim()
    }

    // Без «(feat. …)», «(prod. …)», «[with …]»
    function cleanTitle(t) {
        return (t ?? "").replace(/\s*[([](?:feat|ft|prod|with)\b[^)\]]*[)\]]/gi, "").trim()
    }

    Component {
        id: fetcher
        Process {
            id: req
            property var done
            // В конце вывода — код ответа (-w). 200 — ответ, 404 — точно
            // нет; остальное (000 — не достучались, 5xx) — сбой
            stdout: StdioCollector {
                onStreamFinished: {
                    const cut = text.lastIndexOf("\n")
                    const code = Number(text.slice(cut + 1))
                    let r = null
                    if (code === 200) {
                        try {
                            r = JSON.parse(text.slice(0, cut))
                        } catch (e) {}
                    }
                    req.done(r, code === 404 || (code === 200 && r !== null))
                    req.destroy()
                }
            }
        }
    }

    function get(url, done) {
        const cmd = ["curl", "-sL", "-m", "15", "-w", "\n%{http_code}", "-A", "quickshell-lyrics github.com/MichaAI/quickshell"]
        if (Weather.proxy !== "")
            cmd.push("-x", Weather.proxy)
        cmd.push(url)
        const p = fetcher.createObject(root, { command: cmd, done: done })
        p.running = true
    }
}
