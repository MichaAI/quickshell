pragma Singleton
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"

// Простой: за idleWarnSec до лока — предупреждение (bar/IdleWarning.qml),
// потом лок, потом сон. Таймауты — Settings.idle*. Не засыпать:
// caffeine (руками: бар, «q idle», qs ipc call idle toggle), пока играет
// плеер или пока держит systemd-inhibit (services/Logind.qml).
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

    // Режим: auto — лок, потом сон; lock — только лок; awake — ничего
    property string mode: "auto"
    readonly property bool caffeine: mode === "awake"
    // Не засыпать, пока играет плеер (переключается в «q idle»)
    property bool whilePlaying: Settings.idleWhilePlaying
    readonly property bool playing: whilePlaying && Players.playingList.length > 0
    // Блокирующие инхибиторы logind (systemd-inhibit)
    readonly property bool logindIdle: Logind.blocked.includes("idle")
    readonly property bool logindSleep: Logind.blocked.includes("sleep")
    readonly property bool inhibited: caffeine || playing || logindIdle
    readonly property var modes: ({
        auto: { icon: "󰒲", title: "Лок и сон" },
        lock: { icon: "󰌾", title: "Только лок, без сна" },
        awake: { icon: "󰅶", title: "Не засыпать" }
    })

    readonly property bool warning: warnMon.isIdle && !lockMon.isIdle
    readonly property int warnSec: Math.min(Settings.idleWarnSec, Math.max(0, Settings.idleLockSec - 1))

    function setMode(m) {
        if (modes[m]) mode = m
    }

    // Не засыпать ↔ лок и сон
    function toggle() {
        mode = caffeine ? "auto" : "awake"
    }

    // «лок через 5 мин, сон через 10» / почему не заснёт
    function describe() {
        if (caffeine) return "не засыпаю: включено вручную"
        if (logindIdle) return "не засыпаю: держит " + holders("idle")
        if (playing) return "не засыпаю, пока играет " + (Players.title || "плеер")
        const fmt = s => s % 60 === 0 ? s / 60 + " мин" : s + " с"
        const parts = []
        if (Settings.idleLockSec > 0) parts.push("лок через " + fmt(Settings.idleLockSec))
        if (Settings.idleSuspendSec > 0 && mode === "auto")
            parts.push(logindSleep ? "без сна: держит " + holders("sleep") : "сон через " + fmt(Settings.idleSuspendSec))
        return parts.length ? parts.join(", ") : "простой выключен"
    }

    // «make, steam» — кто держит systemd-inhibit
    function holders(what) {
        const who = Logind.holders(what)
        return who.length ? who.join(", ") : "systemd-inhibit"
    }

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
        enabled: Settings.idleSuspendSec > 0 && root.mode === "auto" && !root.logindSleep && !root.inhibited
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
