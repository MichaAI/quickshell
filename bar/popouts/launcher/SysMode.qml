import QtQuick
import Quickshell.Services.Pipewire
import "../../../config"
import "../../../services"
import "Match.js" as Match

// Система с клавиатуры: «q vol 30», «q vol +5», «q vol mute», «q mic»,
// «q br 70», «q bt», «q wifi», «q mp next». Тема — первое слово после q
// (launcher.topic), arg — что после него; без темы — список команд. Уровни: число — выставить, ±число — сдвинуть, m/mute —
// выключить звук, max — 100. Пустой arg — текущее состояние, Ctrl+←→
// двигает выделенный уровень на 5%. ⏎ — сделать и закрыть, ⇧⏎ — сделать
// и остаться (крутить дальше).
Item {
    id: mode

    required property var launcher

    readonly property string topic: launcher.mode === "sys" ? launcher.topic : ""

    readonly property var topics: ({
        vol:   { icon: "󰕾", color: Theme.mauve,    title: "Громкость",  hint: "Громкость: 30, +5, -10, mute, max · выходы и приложения" },
        mic:   { icon: "󰍬", color: Theme.peach,    title: "Микрофон",   hint: "Микрофон: 50, +5, mute · входы" },
        br:    { icon: "󰃠", color: Theme.yellow,   title: "Яркость",    hint: "Яркость: 70, +10, -10, max" },
        bt:    { icon: "󰂯", color: Theme.blue,     title: "Bluetooth",  hint: "Bluetooth: устройство…   (on / off)" },
        wifi:  { icon: "󰖩", color: Theme.teal,     title: "Wi-Fi",      hint: "Wi-Fi: сеть…   (сеть / пароль, on / off)" },
        media: { icon: "󰝚", color: Theme.pink,     title: "Плеер",      hint: "Плеер: play, next, prev…" },
        idle:  { icon: "󰅶", color: Theme.peach,    title: "Простой", hint: "Простой: лок и сон / только лок / не засыпать" }
    })

    readonly property var info: {
        const t = topics[topic]
        return t ? { icon: t.icon, color: t.color, hint: t.hint } : launcher.modes.sys
    }

    // Громкость приложений видна, только пока их ноды привязаны
    PwObjectTracker {
        objects: mode.topic === "vol" ? [...Audio.streams, ...mode.nodes(PwNodeType.AudioSink)]
               : mode.topic === "mic" ? mode.nodes(PwNodeType.AudioSource) : []
    }

    // «q …» без темы — список команд с текущим состоянием;
    // ⏎ / Tab — зайти в команду
    readonly property var order: [["vol", "vol"], ["mic", "mic"], ["br", "br"], ["bt", "bt"], ["wifi", "wifi"], ["media", "mp"], ["idle", "idle"]]

    function stateOf(t) {
        switch (t) {
        case "vol": return (Audio.muted ? "выкл" : pct(Audio.volume)) + " · " + Audio.sinkName
        case "mic": return (Audio.micMuted ? "выкл" : pct(Audio.micVolume)) + " · " + Audio.sourceName
        case "br": return Brightness.present ? Brightness.percent + "%" : "нет подсветки"
        case "bt": return !Bt.present ? "нет адаптера" : !Bt.enabled ? "выключен" : Bt.connected.length + " подключено"
        case "wifi": return "сети, подключение, вкл/выкл"
        case "media": return Players.active ? Players.title + (Players.artist ? " — " + Players.artist : "") : "ничего не играет"
        case "idle": return Idle.modes[Idle.mode].title + " · " + Idle.describe()
        }
        return ""
    }

    function commandItems(a) {
        return Match.filterBy(order, a.trim(), o => [o[1], topics[o[0]].title]).map(o => {
            const t = topics[o[0]]
            const go = () => launcher.setQuery("q " + o[1] + " ")
            return {
                glyph: t.icon,
                glyphColor: t.color,
                title: o[1] + "   " + t.title,
                sub: stateOf(o[0]),
                progress: o[0] === "vol" ? (Audio.muted ? 0 : Audio.volume)
                    : o[0] === "mic" ? (Audio.micMuted ? 0 : Audio.micVolume)
                    : o[0] === "br" && Brightness.present ? Brightness.value : undefined,
                badge: "⏎ / Tab — q " + o[1] + " …",
                ghostSource: o[1],
                tab: go,
                run: go
            }
        })
    }

    function nodes(type) {
        return Pipewire.nodes.values.filter(n => n.type === type)
    }

    function nodeName(n) {
        return n.description || n.nickname || n.name || "—"
    }

    // «30» / «+5» / «-10» / «m» / «max» → { set } | { delta } | { mute } | null
    function level(a) {
        const s = a.trim().toLowerCase().replace(/%$/, "")
        if (s === "") return null
        if (/^(m|mute|выкл|тихо)$/.test(s)) return { mute: true }
        if (s === "max") return { set: 1 }
        if (/^[+-]\d+(\.\d+)?$/.test(s)) return { delta: parseFloat(s) / 100 }
        if (/^\d+(\.\d+)?$/.test(s)) return { set: Math.min(150, parseFloat(s)) / 100 }
        return null
    }

    function pct(v) { return Math.round(v * 100) + "%" }

    // ⏎ закрывает, ⇧⏎ оставляет лончер открытым
    function act(fn) {
        return shift => {
            fn()
            if (!shift) Ui.closePopouts()
        }
    }

    function items() {
        const a = launcher.arg
        switch (topic) {
        case "vol": return volItems(a)
        case "mic": return micItems(a)
        case "br": return brItems(a)
        case "bt": return btItems(a)
        case "wifi": return wifiItems(a)
        case "media": return mediaItems(a)
        case "idle": return idleItems()
        }
        return commandItems(a)
    }

    // Строка уровня: текущее значение с полосой; с arg — что станет
    function levelRow(o) {
        const lv = level(o.arg)
        const target = lv?.mute ? null
            : lv?.set !== undefined ? lv.set
            : lv?.delta !== undefined ? Math.max(0, Math.min(1, o.value + lv.delta)) : null
        return {
            glyph: o.icon,
            glyphColor: o.muted ? Theme.overlay1 : o.color,
            title: o.title + "   " + (o.muted ? "выкл" : pct(o.value))
                + (target !== null ? "  →  " + pct(target) : lv?.mute ? "  →  " + (o.muted ? "вкл" : "выкл") : ""),
            sub: o.sub,
            progress: o.muted ? 0 : o.value,
            progressTarget: target ?? (lv?.mute ? (o.muted ? o.value : 0) : undefined),
            badge: lv ? "⏎ применить   ⇧⏎ и остаться" : (o.canMute ? "⏎ вкл/выкл звук   " : "") + "Ctrl+←→ ±5%",
            nudge: d => o.set(Math.max(0, Math.min(1, o.value + d * 0.05))),
            run: act(() => {
                if (lv?.mute || !lv && o.canMute) o.toggleMute()
                else if (target !== null) o.set(target)
            })
        }
    }

    function volItems(a) {
        const out = [levelRow({
            arg: a, icon: Audio.icon, color: Theme.mauve, title: "Громкость",
            sub: Audio.sinkName, value: Audio.volume, muted: Audio.muted, canMute: true,
            set: v => Audio.setVolume(v), toggleMute: () => Audio.toggleMute()
        })]
        // Не уровень — значит фильтр по выходам и приложениям
        const q = level(a) ? "" : a.trim()
        const sinks = Match.filterBy(nodes(PwNodeType.AudioSink), q, n => [nodeName(n), n.name])
        for (const n of sinks) {
            const cur = n === Audio.sink
            out.push({
                glyph: cur ? "󰓃" : "󰓄",
                glyphColor: cur ? Theme.mauve : Theme.overlay1,
                title: nodeName(n),
                sub: cur ? "Выход по умолчанию" : "Выход",
                badge: cur ? "" : "⏎ выводить сюда",
                run: act(() => { Pipewire.preferredDefaultAudioSink = n })
            })
        }
        const streams = Match.filterBy(Audio.streams.filter(n => n.audio), q,
            n => [Audio.streamName(n), n.properties?.["media.name"] ?? ""])
        for (const n of streams) {
            const au = n.audio
            out.push({
                glyph: "󰝚",
                glyphColor: au.muted ? Theme.overlay1 : Theme.pink,
                title: Audio.streamName(n) + "   " + (au.muted ? "выкл" : pct(au.volume)),
                sub: n.properties?.["media.name"] ?? "",
                progress: au.volume,
                badge: "⏎ вкл/выкл   Ctrl+←→ ±5%",
                nudge: d => { au.muted = false; au.volume = Math.max(0, Math.min(1, au.volume + d * 0.05)) },
                run: act(() => { au.muted = !au.muted })
            })
        }
        return out
    }

    function micItems(a) {
        const out = [levelRow({
            arg: a, icon: Audio.micMuted ? "󰍭" : "󰍬", color: Theme.peach, title: "Микрофон",
            sub: Audio.sourceName, value: Audio.micVolume, muted: Audio.micMuted, canMute: true,
            set: v => Audio.setMicVolume(v), toggleMute: () => Audio.toggleMicMute()
        })]
        const q = level(a) ? "" : a.trim()
        for (const n of Match.filterBy(nodes(PwNodeType.AudioSource), q, n => [nodeName(n), n.name])) {
            const cur = n === Audio.source
            out.push({
                glyph: cur ? "󰍬" : "󰍮",
                glyphColor: cur ? Theme.peach : Theme.overlay1,
                title: nodeName(n),
                sub: cur ? "Вход по умолчанию" : "Вход",
                badge: cur ? "" : "⏎ слушать этот",
                run: act(() => { Pipewire.preferredDefaultAudioSource = n })
            })
        }
        return out
    }

    function brItems(a) {
        if (!Brightness.present)
            return [{ glyph: "󰃠", glyphColor: Theme.overlay1, title: "Подсветка экрана не найдена",
                      sub: "/sys/class/backlight пуст", run: () => {} }]
        return [levelRow({
            arg: a, icon: Brightness.icon, color: Theme.yellow, title: "Яркость",
            sub: Brightness.device, value: Brightness.value, muted: false, canMute: false,
            set: v => Brightness.set(v), toggleMute: () => {}
        })]
    }

    // ===== Bluetooth =====

    function btItems(a) {
        if (!Bt.present)
            return [{ glyph: "󰂲", glyphColor: Theme.overlay1, title: "Bluetooth-адаптера нет", run: () => {} }]
        const q = a.trim().toLowerCase()
        const out = []
        const onOff = q === "on" || q === "off" || q === "вкл" || q === "выкл"
        if (q === "" || onOff || "bluetooth".startsWith(q)) {
            const want = onOff ? (q === "on" || q === "вкл") : !Bt.enabled
            out.push({
                glyph: Bt.icon,
                glyphColor: Bt.enabled ? Theme.blue : Theme.overlay1,
                title: want ? "Включить Bluetooth" : "Выключить Bluetooth",
                sub: Bt.enabled ? "Сейчас включён · " + Bt.connected.length + " подключено" : "Сейчас выключен",
                badge: "⏎ переключить   ⇧⏎ и остаться",
                run: act(() => { if (Bt.adapter) Bt.adapter.enabled = want })
            })
        }
        if (onOff || !Bt.enabled) return out
        for (const d of Match.filterBy(Bt.devices.filter(d => d.paired || d.connected), q, d => [d.name, d.address])) {
            out.push({
                glyph: Bt.iconOf(d),
                glyphColor: d.connected ? Theme.blue : Theme.overlay1,
                title: d.name || d.address,
                sub: Bt.stateText(d),
                badge: d.connected ? "⏎ отключить" : "⏎ подключить",
                run: act(() => Bt.activate(d))
            })
        }
        return out
    }

    // ===== Плеер =====

    function mediaItems(a) {
        const p = Players.active
        if (!p)
            return [{ glyph: "󰝛", glyphColor: Theme.overlay1, title: "Ничего не играет", run: () => {} }]
        const now = Players.title + (Players.artist ? " — " + Players.artist : "")
        const list = [
            { title: p.isPlaying ? "Пауза" : "Играть", keys: "play pause toggle пауза играть",
              glyph: p.isPlaying ? "󰏤" : "󰐊", ok: p.canTogglePlaying, fn: () => p.togglePlaying() },
            { title: "Следующий трек", keys: "next n след дальше", glyph: "󰒭", ok: p.canGoNext, fn: () => p.next() },
            { title: "Предыдущий трек", keys: "prev previous p пред назад", glyph: "󰒮", ok: p.canGoPrevious, fn: () => p.previous() }
        ]
        return Match.filterBy(list.filter(x => x.ok), a.trim(), x => [x.title, x.keys]).map(x => ({
            glyph: x.glyph,
            glyphColor: Theme.pink,
            title: x.title,
            sub: now,
            badge: "⏎ сделать   ⇧⏎ и остаться",
            ghostSource: x.title,
            run: act(x.fn)
        }))
    }

    // ===== Wi-Fi (nmcli) =====
    // «wifi сеть» — фильтр, «wifi сеть / пароль» — подключиться с паролем

    property var nets: []          // [{ ssid, signal, secure, inUse }]
    property var known: []         // имена сохранённых wifi-подключений
    property bool radio: true
    property bool scanning: false
    property bool hasNmcli: true

    onTopicChanged: if (topic === "wifi") refreshWifi(false)

    // nmcli -t экранирует «:» и «\» обратной чертой
    function splitTerse(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const ch = line[i]
            if (ch === "\\" && i + 1 < line.length) cur += line[++i]
            else if (ch === ":") { out.push(cur); cur = "" }
            else cur += ch
        }
        out.push(cur)
        return out
    }

    function refreshWifi(rescan) {
        scanning = true
        Tools.run(["nmcli", "-t", "radio", "wifi"], (code, out) => {
            if (!mode) return
            mode.hasNmcli = code !== 127
            mode.radio = out.trim() === "enabled"
        })
        Tools.run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"], (code, out) => {
            if (!mode || code !== 0) return
            mode.known = out.split("\n").map(splitTerse)
                .filter(f => f[1] === "802-11-wireless").map(f => f[0])
        })
        listWifi()
        // Сначала — что NetworkManager уже знает, потом пересканировать
        // фоном (может занять несколько секунд) и показать заново
        if (rescan || nets.length === 0)
            Tools.run(["nmcli", "device", "wifi", "rescan"], () => {
                if (!mode) return
                mode.scanning = false
                mode.listWifi()
            })
        else
            scanning = false
    }

    function listWifi() {
        Tools.run(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list",
                   "--rescan", "no"], (code, out) => {
            if (!mode) return
            if (code !== 0) { mode.scanning = false; return }
            const seen = {}
            const list = []
            for (const l of out.split("\n")) {
                if (l === "") continue
                const f = splitTerse(l)
                const n = { inUse: f[0] === "*", ssid: f[1], signal: parseInt(f[2]) || 0, secure: (f[3] ?? "") !== "" && f[3] !== "--" }
                if (n.ssid === "") continue
                // Одна сеть на нескольких точках — берём сильнейшую
                const prev = seen[n.ssid]
                if (prev) { prev.inUse = prev.inUse || n.inUse; continue }
                seen[n.ssid] = n
                list.push(n)
            }
            list.sort((x, y) => (y.inUse - x.inUse) || (y.signal - x.signal))
            mode.nets = list
        })
    }

    function connectWifi(n, pass, shift) {
        const cmd = mode.known.includes(n.ssid) && pass === ""
            ? ["nmcli", "connection", "up", "id", n.ssid]
            : ["nmcli", "device", "wifi", "connect", n.ssid, ...(pass !== "" ? ["password", pass] : [])]
        Tools.run(cmd, (code, out, err) => {
            if (code === 0) {
                Zsh.notify("low", "Wi-Fi", "Подключено: " + n.ssid)
            } else {
                const e = (err || out).trim()
                Zsh.notify("normal", "Wi-Fi: " + n.ssid,
                    n.secure && pass === "" ? "Нужен пароль: wifi " + n.ssid + " / пароль" : e || "nmcli: код " + code)
            }
            if (mode) mode.refreshWifi(false)
        })
        if (!shift) Ui.closePopouts()
    }

    function wifiItems(a) {
        if (!hasNmcli)
            return [{ glyph: "󰖪", glyphColor: Theme.red, title: "nmcli не найден", sub: "Нужен NetworkManager", run: () => {} }]
        const slash = a.indexOf(" / ")
        const q = (slash >= 0 ? a.slice(0, slash) : a).trim()
        const pass = slash >= 0 ? a.slice(slash + 3) : ""
        const lq = q.toLowerCase()
        const onOff = lq === "on" || lq === "off" || lq === "вкл" || lq === "выкл"
        const out = []
        if (lq === "" || onOff) {
            const want = onOff ? (lq === "on" || lq === "вкл") : !radio
            out.push({
                glyph: radio ? "󰖩" : "󰖪",
                glyphColor: radio ? Theme.teal : Theme.overlay1,
                title: want ? "Включить Wi-Fi" : "Выключить Wi-Fi",
                sub: radio ? (scanning ? "Ищу сети…" : nets.length + " сетей рядом") : "Сейчас выключен",
                progress: scanning ? -1 : undefined,
                badge: "⏎ переключить   Tab пересканировать",
                tab: () => mode.refreshWifi(true),
                run: shift => {
                    Tools.run(["nmcli", "radio", "wifi", want ? "on" : "off"], () => {
                        if (mode) Qt.callLater(() => mode.refreshWifi(want))
                    })
                    if (!shift) Ui.closePopouts()
                }
            })
        }
        if (onOff || !radio) return out
        for (const n of Match.filterBy(nets, q, n => [n.ssid])) {
            const saved = known.includes(n.ssid)
            const bars = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"][Math.min(4, Math.floor(n.signal / 20))]
            out.push({
                glyph: bars,
                glyphColor: n.inUse ? Theme.teal : Theme.overlay1,
                title: n.ssid,
                sub: (n.inUse ? "Подключено · " : saved ? "Сохранена · " : "")
                    + n.signal + "%" + (n.secure ? " · 󰌾" : " · открытая"),
                badge: n.inUse ? "" : pass !== "" ? "⏎ подключиться с паролем"
                    : n.secure && !saved ? "сеть / пароль ⏎" : "⏎ подключиться",
                noHistory: pass !== "",
                ghostSource: n.ssid,
                run: shift => { if (!n.inUse) mode.connectWifi(n, pass, shift) }
            })
        }
        return out
    }

    function idleItems() {
        return ["auto", "lock", "awake"].map(m => {
            const cur = m === Idle.mode
            return {
                glyph: Idle.modes[m].icon,
                glyphColor: cur ? Theme.peach : Theme.overlay1,
                title: Idle.modes[m].title,
                sub: cur ? Idle.describe() : "",
                badge: cur ? "" : "⏎ включить",
                run: act(() => Idle.setMode(m))
            }
        })
    }
}
