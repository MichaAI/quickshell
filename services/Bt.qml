pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import QtQuick

// Bluetooth: адаптер и устройства (BlueZ через Quickshell.Bluetooth).
// Наушники с управлением — отдельно, в Buds.
Singleton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool present: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool scanning: adapter?.discovering ?? false

    // Подключённые, потом спаренные, потом найденные поиском. Найденные
    // без имени (только адрес) не показываем — их не узнать
    readonly property var devices: (adapter?.devices.values ?? [])
        .filter(d => d.paired || d.connected || (d.name !== "" && d.name.replace(/[-_]/g, ":") !== d.address))
        .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
    readonly property var connected: devices.filter(d => d.connected)

    readonly property string icon: !enabled ? "󰂲" : connected.length > 0 ? "󰂱" : "󰂯"

    function toggle() {
        if (adapter)
            adapter.enabled = !adapter.enabled
    }

    function scan(on) {
        if (adapter && adapter.enabled)
            adapter.discovering = on
    }

    // Клик по устройству: подключить, отключить или спарить (подключится
    // само, как только спарится — см. BluetoothPopout)
    function activate(dev) {
        if (dev.connected)
            dev.disconnect()
        else if (dev.paired)
            dev.connect()
        else {
            dev.trusted = true
            dev.pair()
        }
    }

    // Значок по типу из BlueZ (freedesktop icon name)
    function iconOf(dev) {
        const i = dev?.icon ?? ""
        if (i.startsWith("audio-headphones") || i.startsWith("audio-headset")) return "󰋋"
        if (i.startsWith("audio-card") || i.startsWith("audio-speakers")) return "󰓃"
        if (i.startsWith("input-keyboard")) return "󰌌"
        if (i.startsWith("input-mouse")) return "󰍽"
        if (i.startsWith("input-gaming")) return "󰊴"
        if (i.startsWith("input-tablet")) return "󰓶"
        if (i.startsWith("phone")) return "󰄜"
        if (i.startsWith("computer")) return "󰟀"
        if (i.startsWith("video-display")) return "󰍹"
        if (i.startsWith("camera")) return "󰄀"
        if (i.startsWith("printer")) return "󰐪"
        return "󰂯"
    }

    function stateText(dev) {
        if (dev.pairing) return "Сопряжение…"
        switch (dev.state) {
        case BluetoothDeviceState.Connecting: return "Подключаюсь…"
        case BluetoothDeviceState.Disconnecting: return "Отключаюсь…"
        }
        if (dev.connected)
            return dev.batteryAvailable ? "Подключено · " + Math.round(dev.battery * 100) + "%" : "Подключено"
        return dev.paired ? "Сопряжено" : "Новое"
    }
}
