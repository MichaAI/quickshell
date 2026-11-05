pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../config"

// Простой: за idleWarnSec до лока — предупреждение (bar/IdleWarning.qml),
// потом лок, потом сон. Таймауты — Settings.idle*.
//
// Не засыпать (ни лока, ни сна), если: включено руками на время или
// бессрочно (бар, «q idle», qs ipc call idle …), играет плеер (тумблер
// whilePlaying) или держит systemd-inhibit --what=idle
// (services/Logind.qml); --what=sleep запрещает только сон. Оба тумблера
// переживают перезапуск: ~/.cache/quickshell-idle.json.
//
// Свои запреты выключают мониторы ниже напрямую: niri уважает
// IdleInhibitor бара, только пока бар отрисован, а под полноэкранным
// окном его нет (niri#2028). IdleInhibitor в баре — для чужих мониторов
// простоя. Включённый заново монитор отсчитывает простой с нуля — снятый
// запрет не лочит сразу.
//
// Лок перед сном (крышка, systemctl suspend, сон отсюда же) — свой
// delay-инхибитор logind: сон ждёт, пока лок не закроет экран (не дольше
// InhibitDelayMaxSec). Ещё logind знает LockedHint и IdleHint сессии, а
// loginctl lock-session закрывает экран
Singleton {
    id: root

    // Не засыпать руками: 0 — выкл, -1 — пока не выключат, иначе до этого
    // времени (мс с эпохи)
    property real awakeUntil: 0
    readonly property bool caffeine: awakeUntil !== 0
    // Не засыпать, пока играет плеер
    property bool whilePlaying: Settings.idleWhilePlaying
    readonly property bool playing: whilePlaying && Players.playingList.length > 0
    // Блокирующие инхибиторы logind (systemd-inhibit)
    readonly property bool logindIdle: Logind.blocked.includes("idle")
    readonly property bool logindSleep: Logind.blocked.includes("sleep")
    readonly property bool inhibited: caffeine || playing || logindIdle

    readonly property bool warning: warnMon.isIdle && !lockMon.isIdle
    readonly property int warnSec: Math.min(Settings.idleWarnSec, Math.max(0, Settings.idleLockSec - 1))

    // Не засыпать: minutes > 0 — на столько минут, -1 — пока не выключат,
    // 0 — выключить
    function stayAwake(minutes) {
        now = Date.now()
        awakeUntil = minutes > 0 ? now + minutes * 60000 : minutes < 0 ? -1 : 0
    }

    function toggle() {
        stayAwake(caffeine ? 0 : -1)
    }

    // Что сейчас и почему — одной строкой: для бара, «q idle» и IPC.
    // awake — что-то держит, icon — что именно
    readonly property var status: {
        if (awakeUntil < 0)
            return { awake: true, icon: "󰅶", text: "Не засыпаю, пока не выключишь" }
        if (awakeUntil > 0)
            return { awake: true, icon: "󰅶", text: "Не засыпаю ещё " + left(awakeUntil - now) }
        if (logindIdle)
            return { awake: true, icon: "󰒳", text: "Не засыпаю: держит " + holders("idle") }
        if (playing)
            return { awake: true, icon: "󰝚", text: "Не засыпаю, пока играет " + (Players.title || "плеер") }
        const fmt = s => s % 60 === 0 ? s / 60 + " мин" : s + " с"
        const parts = []
        if (Settings.idleLockSec > 0)
            parts.push("лок через " + fmt(Settings.idleLockSec))
        if (Settings.idleSuspendSec > 0)
            parts.push(logindSleep ? "без сна: держит " + holders("sleep") : "сон через " + fmt(Settings.idleSuspendSec))
        const text = parts.join(", ")
        return { awake: false, icon: "󰒲", text: text ? "Без движения: " + text : "Простой выключен" }
    }

    // «30 с», «47 мин», «1 ч 05 мин»
    function left(ms) {
        const s = Math.max(0, Math.ceil(ms / 1000))
        if (s < 60)
            return s + " с"
        const m = Math.ceil(s / 60)
        return m < 60 ? m + " мин" : Math.floor(m / 60) + " ч " + String(m % 60).padStart(2, "0") + " мин"
    }

    // «make, steam» — кто держит systemd-inhibit
    function holders(what) {
        const who = Logind.holders(what)
        return who.length ? who.join(", ") : "systemd-inhibit"
    }

    // Часы для «ещё 47 мин» — тикают, только пока идёт отсчёт
    property real now: Date.now()
    Timer {
        running: root.awakeUntil > 0
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now()
            if (root.now >= root.awakeUntil)
                root.awakeUntil = 0
        }
    }

    // Оба тумблера — в файл, чтобы пережить перезапуск шелла
    property bool loaded: false
    onAwakeUntilChanged: save()
    onWhilePlayingChanged: save()
    function save() {
        if (loaded)
            store.setText(JSON.stringify({ awakeUntil, whilePlaying }) + "\n")
    }

    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.cache/quickshell-idle.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const v = JSON.parse(text())
                // Истёкший таймер не воскрешаем
                if (typeof v.awakeUntil === "number" && (v.awakeUntil < 0 || v.awakeUntil > Date.now()))
                    root.awakeUntil = v.awakeUntil
                if (typeof v.whilePlaying === "boolean")
                    root.whilePlaying = v.whilePlaying
            } catch (e) {}
        }
    }
    Component.onCompleted: loaded = true

    IdleMonitor {
        id: warnMon
        enabled: Settings.idleLockSec > 0 && root.warnSec > 0 && !root.inhibited
        timeout: Math.max(1, Settings.idleLockSec - root.warnSec)
        respectInhibitors: true
    }

    IdleMonitor {
        id: lockMon
        enabled: Settings.idleLockSec > 0 && !root.inhibited
        timeout: Math.max(1, Settings.idleLockSec)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) Ui.lockRequested()
    }

    IdleMonitor {
        id: sleepMon
        enabled: Settings.idleSuspendSec > 0 && !root.logindSleep && !root.inhibited
        timeout: Math.max(1, Settings.idleSuspendSec)
        respectInhibitors: true
        // Без tty systemctl инхибиторы не проверяет, а logind пропускает
        // блокировки того же пользователя — просим проверить явно
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["systemctl", "sleep", "--check-inhibitors=yes"])
    }

    // Лок перед сном: экран должен закрыться до засыпания, иначе после
    // пробуждения мелькнёт рабочий стол
    property bool sleepPending: false

    Binding {
        target: Logind
        property: "guardSleep"
        value: true
    }
    Binding {
        target: Logind
        property: "locked"
        value: Ui.locked
    }
    Binding {
        target: Logind
        property: "idle"
        value: lockMon.isIdle
    }

    Connections {
        target: Logind
        function onPrepareForSleep(start) {
            root.sleepPending = start && !Ui.locked
            if (!start)
                return
            Ui.lockRequested()
            if (Ui.locked)
                Logind.sleepReady()
        }
        function onLockRequested() {
            Ui.lockRequested()
        }
    }

    Connections {
        target: Ui
        function onLockedChanged() {
            if (Ui.locked && root.sleepPending) {
                root.sleepPending = false
                Logind.sleepReady()
            }
        }
    }
}
