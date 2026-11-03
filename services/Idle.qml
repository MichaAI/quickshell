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

    property bool caffeine: false
    readonly property bool playing: Settings.idleWhilePlaying && Players.playingList.length > 0
    readonly property bool inhibited: caffeine || playing

    readonly property bool warning: warnMon.isIdle && !lockMon.isIdle
    readonly property int warnSec: Math.min(Settings.idleWarnSec, Math.max(0, Settings.idleLockSec - 1))

    function toggle() {
        caffeine = !caffeine
    }

    // «лок через 5 мин, сон через 10» / почему не заснёт
    function describe() {
        if (caffeine) return "не засыпаю: включено вручную"
        if (playing) return "не засыпаю, пока играет " + (Players.title || "плеер")
        const fmt = s => s % 60 === 0 ? s / 60 + " мин" : s + " с"
        const parts = []
        if (Settings.idleLockSec > 0) parts.push("лок через " + fmt(Settings.idleLockSec))
        if (Settings.idleSuspendSec > 0) parts.push("сон через " + fmt(Settings.idleSuspendSec))
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
        enabled: Settings.idleSuspendSec > 0
        timeout: Math.max(1, Settings.idleSuspendSec)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["systemctl", "sleep"])
    }
}
