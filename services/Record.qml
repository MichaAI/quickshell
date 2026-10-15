pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Кто сейчас пишет экран (трансляции niri) и микрофон (PipeWire)
Singleton {
    id: root

    readonly property var casts: Niri.casts
    readonly property bool screen: casts.length > 0

    // Захват микрофона: связь от источника-устройства к потоку записи.
    // Монитор колонок (cava, визуализаторы) идёт от sink'а — его не считаем.
    // Только type и name: properties есть лишь у привязанных нод (см. Audio.qml)
    readonly property var micUsers: {
        const names = []
        for (const g of Pipewire.linkGroups.values) {
            if (g.source?.type !== PwNodeType.AudioSource || g.target?.type !== PwNodeType.AudioInStream)
                continue
            const n = g.target.name || "?"
            if (!names.includes(n))
                names.push(n)
        }
        return names
    }
    readonly property bool mic: micUsers.length > 0
    readonly property bool active: screen || mic

    // Что пишут: экран, окно или пусто — для подписи на баре
    readonly property string screenLabel: {
        if (!screen)
            return ""
        const t = casts[0].target
        let label = "Экран"
        if (t?.Window) {
            const w = Niri.windows.find(x => x.id === t.Window.id)
            label = w?.app_id || "Окно"
        } else if (t?.Output) {
            label = t.Output.name
        }
        return casts.length > 1 ? label + " +" + (casts.length - 1) : label
    }

    // Время с начала самой старой трансляции
    property var started: ({})
    property double since: 0
    onCastsChanged: {
        const now = Date.now()
        const next = {}
        for (const c of casts)
            next[c.stream_id] = started[c.stream_id] ?? now
        started = next
        const times = Object.values(next)
        since = times.length > 0 ? Math.min(...times) : 0
    }

    property double now: Date.now()
    Timer {
        interval: 1000
        running: root.screen
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    readonly property string elapsed: {
        if (!screen)
            return ""
        const s = Math.max(0, Math.floor((now - since) / 1000))
        const mm = Math.floor(s / 60), ss = s % 60
        const h = Math.floor(mm / 60)
        const pad = v => (v < 10 ? "0" : "") + v
        return h > 0 ? h + ":" + pad(mm % 60) + ":" + pad(ss) : pad(mm) + ":" + pad(ss)
    }

    // PipeWire-трансляции niri умеет остановить, wlr-screencopy — нет
    function stopAll() {
        const sessions = new Set(casts.filter(c => c.kind === "PipeWire").map(c => c.session_id))
        for (const id of sessions)
            Niri.stopCast(id)
    }
}
