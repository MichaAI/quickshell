import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "Match.js" as Match

// «!» — действия: питание, скриншоты, пипетка, уведомления.
// Опасные просят второй Enter.
Item {
    id: mode

    required property var launcher

    property string confirmId: ""

    readonly property var list: [
        { id: "lock", glyph: "󰌾", title: "Заблокировать", sub: "Экран блокировки шелла", fn: () => Ui.lockRequested() },
        { id: "suspend", glyph: "󰒲", title: "Сон", sub: "systemctl suspend", cmd: ["systemctl", "suspend"] },
        { id: "poweroff", glyph: "󰐥", title: "Выключить", sub: "systemctl poweroff", cmd: ["systemctl", "poweroff"], confirm: true },
        { id: "reboot", glyph: "󰜉", title: "Перезагрузить", sub: "systemctl reboot", cmd: ["systemctl", "reboot"], confirm: true },
        { id: "logout", glyph: "󰍃", title: "Выйти из niri", sub: "niri msg action quit", cmd: ["niri", "msg", "action", "quit", "--skip-confirmation"], confirm: true },
        { id: "monitors", glyph: "󰶐", title: "Выключить мониторы", sub: "до первого движения мыши", cmd: ["niri", "msg", "action", "power-off-monitors"] },
        { id: "shot", glyph: "󰹑", title: "Скриншот области", sub: "niri: screenshot", cmd: ["niri", "msg", "action", "screenshot"] },
        { id: "shotscreen", glyph: "󰍹", title: "Скриншот экрана", sub: "niri: screenshot-screen", cmd: ["niri", "msg", "action", "screenshot-screen"] },
        { id: "shotwin", glyph: "󱂬", title: "Скриншот окна", sub: "niri: screenshot-window", cmd: ["niri", "msg", "action", "screenshot-window"] },
        { id: "pick", glyph: "󰈊", title: "Пипетка", sub: "Взять цвет с экрана", fn: () => Tools.pickColor() },
        { id: "wheel", glyph: "󰏘", title: "Выбор цвета", sub: "Колесо, яркость, прозрачность, форматы", keep: true, fn: () => launcher.openPicker("") },
        { id: "dnd", glyph: "󰂛", title: "Не беспокоить", sub: Notifs.dnd ? "Сейчас: включено" : "Сейчас: выключено", keep: true, fn: () => Notifs.toggleDnd() },
        { id: "clearnotif", glyph: "󰎟", title: "Очистить уведомления", sub: Notifs.count + " в центре", fn: () => Notifs.clearAll() }
    ]

    function items(q) {
        return Match.filterBy(list, q, a => [a.title, a.id]).map(a => ({
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
