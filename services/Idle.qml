pragma Singleton
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"

// Простой: за idleWarnSec до лока — предупреждение (bar/IdleWarning.qml),
// потом лок, потом сон. Таймауты — Settings.idle*. Не засыпать:
// caffeine (руками: бар, «q idle», qs ipc call idle toggle) или пока
// играет плеер. Запрет — через IdleInhibitor в окне бара, его уважают и
// мониторы ниже, и чужие (swayidle). Лок перед сном (before-sleep через
// logind) остаётся за swayidle: у шелла нет delay-инхибитора logind
Singleton {
    id: root

    // Режим: auto — лок, потом сон; lock — только лок; awake — ничего
    property string mode: "auto"
    readonly property bool caffeine: mode === "awake"
    readonly property bool playing: Settings.idleWhilePlaying && Players.playingList.length > 0
    readonly property bool inhibited: caffeine || playing
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
        if (playing) return "не засыпаю, пока играет " + (Players.title || "плеер")
        const fmt = s => s % 60 === 0 ? s / 60 + " мин" : s + " с"
        const parts = []
        if (Settings.idleLockSec > 0) parts.push("лок через " + fmt(Settings.idleLockSec))
        if (Settings.idleSuspendSec > 0 && mode === "auto") parts.push("сон через " + fmt(Settings.idleSuspendSec))
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
        enabled: Settings.idleSuspendSec > 0 && root.mode === "auto"
        timeout: Math.max(1, Settings.idleSuspendSec)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["systemctl", "sleep"])
    }
}
