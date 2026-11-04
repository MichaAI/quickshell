pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Подсветка экрана: читаем sysfs, пишем через brightnessctl (он умеет
// менять яркость через logind без прав на запись в sysfs)
Singleton {
    id: root

    property string device: ""
    readonly property bool present: device !== "" && max > 0
    property int max: 0
    property int raw: 0
    readonly property real value: present ? raw / max : 0
    readonly property int percent: Math.round(value * 100)

    readonly property string icon: {
        const icons = ["󰃞", "󰃟", "󰃝", "󰃠"]
        return icons[Math.min(3, Math.floor(value * 4))]
    }

    function set(v) {
        if (!present) return
        const p = Math.round(Math.max(0.01, Math.min(1, v)) * 100)
        raw = Math.round(p / 100 * max)
        Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", p + "%"])
        // Не перечитывать sysfs, пока brightnessctl не успел записать
        if (poll.running)
            poll.restart()
    }

    function change(delta) {
        set(value + delta)
    }

    readonly property string dir: "/sys/class/backlight/" + device + "/"

    Process {
        running: true
        command: ["ls", "/sys/class/backlight"]
        stdout: StdioCollector {
            onStreamFinished: root.device = this.text.split("\n").find(s => s !== "") ?? ""
        }
    }

    FileView {
        path: root.device !== "" ? root.dir + "max_brightness" : ""
        printErrors: false
        onLoaded: root.max = parseInt(text()) || 0
    }

    // Яркость могут поменять клавишами мимо нас. Ядро шлёт uevent на каждое
    // изменение (и с клавиш, и записью в sysfs) — перечитываем сразу; опрос
    // ниже — запасной, только если udevadm нет или он упал
    Process {
        id: udev
        running: root.device !== ""
        command: ["udevadm", "monitor", "--udev", "-s", "backlight"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes(root.device))
                    cur.reload()
            }
        }
    }

    FileView {
        id: cur
        path: root.device !== "" ? root.dir + "brightness" : ""
        printErrors: false
        onLoaded: root.raw = parseInt(text()) || 0
    }

    Timer {
        id: poll
        running: root.present && !udev.running
        interval: 1000
        repeat: true
        onTriggered: cur.reload()
    }
}
