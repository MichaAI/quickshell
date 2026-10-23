import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "Match.js" as Match

// «!» — действия: питание, скриншоты, пипетка, уведомления.
// Опасные просят второй Enter. when: false — композитор такого не умеет
Item {
    id: mode

    required property var launcher

    property string confirmId: ""

    readonly property var list: [
        { id: "lock", glyph: "󰌾", title: "Заблокировать", sub: "Экран блокировки шелла", fn: () => Ui.lockRequested() },
        { id: "suspend", glyph: "󰒲", title: "Сон", sub: "systemctl suspend", cmd: ["systemctl", "suspend"] },
        { id: "poweroff", glyph: "󰐥", title: "Выключить", sub: "systemctl poweroff", cmd: ["systemctl", "poweroff"], confirm: true },
        { id: "reboot", glyph: "󰜉", title: "Перезагрузить", sub: "systemctl reboot", cmd: ["systemctl", "reboot"], confirm: true },
        { id: "logout", glyph: "󰍃", title: "Выйти из " + Compositor.name, sub: Compositor.name + ": quit", fn: () => Compositor.quit(), confirm: true, when: Compositor.name !== "" },
        { id: "monitors", glyph: "󰶐", title: "Выключить мониторы", sub: "до первого движения мыши", fn: () => Compositor.powerOffMonitors(), when: Compositor.canPowerOffMonitors },
        { id: "shot", glyph: "󰹑", title: "Скриншот области", sub: Compositor.name + ": screenshot", fn: () => Compositor.screenshot("area"), when: Compositor.name !== "" },
        { id: "shotscreen", glyph: "󰍹", title: "Скриншот экрана", sub: Compositor.name + ": screenshot-screen", fn: () => Compositor.screenshot("screen"), when: Compositor.name !== "" },
        { id: "shotwin", glyph: "󱂬", title: "Скриншот окна", sub: Compositor.name + ": screenshot-window", fn: () => Compositor.screenshot("window"), when: Compositor.name !== "" },
        { id: "pick", glyph: "󰈊", title: "Пипетка", sub: "Взять цвет с экрана", fn: () => Tools.pickColor(), when: Compositor.canPickColor },
        { id: "wheel", glyph: "󰏘", title: "Выбор цвета", sub: "Колесо, яркость, прозрачность, форматы", keep: true, fn: () => launcher.openPicker("") },
        { id: "dnd", glyph: "󰂛", title: "Не беспокоить", sub: Notifs.dnd ? "Сейчас: включено" : "Сейчас: выключено", keep: true, fn: () => Notifs.toggleDnd() },
        { id: "clearnotif", glyph: "󰎟", title: "Очистить уведомления", sub: Notifs.count + " в центре", fn: () => Notifs.clearAll() }
    ]

    function items(q) {
        return Match.filterBy(list.filter(a => a.when ?? true), q, a => [a.title, a.id]).map(a => ({
            glyph: a.glyph,
            glyphColor: a.confirm ? Theme.red : Theme.mauve,
            title: a.title,
            sub: confirmId === a.id ? "Нажми Enter ещё раз, чтобы подтвердить" : a.sub,
            subColor: confirmId === a.id ? Theme.red : undefined,
            ghostSource: a.title,
            run: () => {
                if (a.confirm && confirmId !== a.id) {
                    mode.confirmId = a.id
                    return
                }
                mode.confirmId = ""
                if (!a.keep) Ui.closePopouts()
                if (a.fn) a.fn()
                else Quickshell.execDetached(a.cmd)
            }
        }))
    }
}
