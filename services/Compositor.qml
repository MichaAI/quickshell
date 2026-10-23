pragma Singleton
import QtQuick
import Quickshell

// Окна, раскладка и действия композитора — одним интерфейсом для бара, лока
// и лончера. Под капотом niri или driftwm, смотря кто запустил шелл.
// Чего бэкенд не умеет, видно по has*/can* — виджеты это просто прячут
Singleton {

    id: root

    // niri кладёт детям NIRI_SOCKET, driftwm — XDG_CURRENT_DESKTOP=driftwm
    // (niri-session тоже ставит XDG_CURRENT_DESKTOP=niri). Под чем-то
    // третьим бэкенда нет: свойства пустые, действия ничего не делают
    readonly property string name: {
        const desktops = (Quickshell.env("XDG_CURRENT_DESKTOP") ?? "").toLowerCase().split(":")
        if (Quickshell.env("NIRI_SOCKET") || desktops.includes("niri"))
            return "niri"
        if (desktops.includes("driftwm"))
            return "driftwm"
        return ""
    }

    readonly property var backend: name === "niri" ? niri : name === "driftwm" ? drift : null

    NiriBackend { id: niri; active: root.name === "niri" }
    DriftBackend { id: drift; active: root.name === "driftwm" }

    // ====== Что умеет ======
    readonly property bool hasWorkspaces: backend?.hasWorkspaces ?? false
    readonly property bool hasCasts: backend?.hasCasts ?? false
    readonly property bool canPowerOffMonitors: backend?.canPowerOffMonitors ?? false
    readonly property var pickColorCommand: backend?.pickColorCommand ?? []
    readonly property bool canPickColor: pickColorCommand.length > 0

    // ====== Состояние ======
    readonly property var workspaces: backend?.workspaces ?? []
    readonly property var windows: backend?.windows ?? []
    readonly property int focusedWindowId: backend?.focusedWindowId ?? -1
    readonly property var focusedWindow: backend?.focusedWindow ?? null
    readonly property string focusedOutput: backend?.focusedOutput ?? ""
    readonly property bool overviewOpen: backend?.overviewOpen ?? false
    readonly property var casts: backend?.casts ?? []
    readonly property string currentLang: backend?.currentLang ?? ""

    // Коротко для бара и лока: RU / EN / первые две буквы
    readonly property string langShort: {
        const l = currentLang
        if (l.indexOf("Russian") !== -1 || l.indexOf("рус") !== -1)
            return "RU"
        if (l.indexOf("English") !== -1)
            return "EN"
        return l.substring(0, 2).toUpperCase()
    }

    // ====== Действия ======
    function focusWindow(id) { backend?.focusWindow(id) }
    function closeWindow(id) { backend?.closeWindow(id) }
    function switchLayout() { backend?.switchLayout() }
    function stopCast(sessionId) { backend?.stopCast(sessionId) }
    function toggleOverview() { backend?.toggleOverview() }
    function quit() { backend?.quit() }
    function powerOffMonitors() { backend?.powerOffMonitors() }
    // area — выделить мышью, screen — монитор, window — окно в фокусе
    function screenshot(target) { backend?.screenshot(target) }
}
