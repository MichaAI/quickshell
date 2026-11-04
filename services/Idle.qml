pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../config"

// Простой: за idleWarnSec до лока — предупреждение (bar/IdleWarning.qml),
// потом лок, потом сон. Таймауты — Settings.idle*. Не засыпать:
// caffeine (руками: бар, «q idle», qs ipc call idle toggle) или пока
// играет плеер. Запрет — через IdleInhibitor в окне бара, его уважают и
// мониторы ниже, и чужие (swayidle). Лок перед сном (before-sleep через
// logind) остаётся за swayidle: у шелла нет delay-инхибитора logind.
// Блокировки logind (systemd-inhibit --what=idle/sleep) мониторы Wayland
// не видят — их опрашиваем сами: idle держит наш IdleInhibitor, sleep
// отменяет сон
Singleton {
    id: root

    // Режим: auto — лок, потом сон; lock — только лок; awake — ничего
    property string mode: "auto"
    readonly property bool caffeine: mode === "awake"
    // Не засыпать, пока играет плеер (переключается в «q idle»)
    property bool whilePlaying: Settings.idleWhilePlaying
    readonly property bool playing: whilePlaying && Players.playingList.length > 0
    // Блокирующие инхибиторы logind: "idle", "sleep", "shutdown"…
    property var logindBlock: []
    readonly property bool logindIdle: logindBlock.includes("idle")
    readonly property bool logindSleep: logindBlock.includes("sleep")
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
        if (logindIdle) return "не засыпаю: держит systemd-inhibit"
        if (playing) return "не засыпаю, пока играет " + (Players.title || "плеер")
        const fmt = s => s % 60 === 0 ? s / 60 + " мин" : s + " с"
        const parts = []
        if (Settings.idleLockSec > 0) parts.push("лок через " + fmt(Settings.idleLockSec))
        if (Settings.idleSuspendSec > 0 && mode === "auto")
            parts.push(logindSleep ? "без сна: держит systemd-inhibit" : "сон через " + fmt(Settings.idleSuspendSec))
        return parts.length ? parts.join(", ") : "простой выключен"
    }

    IdleMonitor {
        id: warnMon
        enabled: Settings.idleLockSec > 0 && root.warnSec > 0
        timeout: Math.max(1, Settings.idleLockSec - root.warnSec)
        respectInhibitors: true
    }

    IdleMonitor {
        id: lockMon
        enabled: Settings.idleLockSec > 0
        timeout: Math.max(1, Settings.idleLockSec)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) Ui.lockRequested()
    }

    IdleMonitor {
        id: sleepMon
        enabled: Settings.idleSuspendSec > 0 && root.mode === "auto" && !root.logindSleep
        timeout: Math.max(1, Settings.idleSuspendSec)
        respectInhibitors: true
        // Без tty systemctl инхибиторы не проверяет, а logind пропускает
        // блокировки того же пользователя — просим проверить явно
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["systemctl", "sleep", "--check-inhibitors=yes"])
    }

    // BlockInhibited изменений не шлёт — опрос
    Process {
        id: blockProc
        command: ["busctl", "get-property", "org.freedesktop.login1", "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager", "BlockInhibited"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = this.text.match(/"(.*)"/)
                const list = m ? m[1].split(":").filter(s => s !== "") : []
                if (list.join(":") !== root.logindBlock.join(":"))
                    root.logindBlock = list
            }
        }
    }

    Timer {
        interval: 15000
        running: Settings.idleLockSec > 0 || Settings.idleSuspendSec > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: blockProc.running = true
    }
}
