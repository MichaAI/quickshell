pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isLaptopBattery
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: device
        ? device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.FullyCharged
        : false
    readonly property bool critical: !charging && percent <= 10

    readonly property string stateText: {
        if (!device) return "—"
        switch (device.state) {
        case UPowerDeviceState.Charging: return "Заряжается"
        case UPowerDeviceState.Discharging: return "Разряжается"
        case UPowerDeviceState.FullyCharged: return "Заряжена"
        case UPowerDeviceState.PendingCharge: return "Ожидание зарядки"
        case UPowerDeviceState.PendingDischarge: return "Ожидание разрядки"
        case UPowerDeviceState.Empty: return "Пусто"
        default: return "Неизвестно"
        }
    }

    readonly property string icon: {
        if (charging) return "󰂄"
        const icons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
        return icons[Math.max(0, Math.min(9, Math.floor(percent / 10)))]
    }

    function fmtSeconds(s) {
        if (s <= 0) return "—"
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        return h > 0 ? `${h} ч ${m} мин` : `${m} мин`
    }

    readonly property string timeText: {
        if (!device) return "—"
        if (device.state === UPowerDeviceState.Charging)
            return device.timeToFull > 0 ? "До полной: " + fmtSeconds(device.timeToFull) : "—"
        if (device.state === UPowerDeviceState.Discharging)
            return device.timeToEmpty > 0 ? "Осталось: " + fmtSeconds(device.timeToEmpty) : "—"
        return ""
    }
}
