pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Мелкие системные действия, которые должны пережить закрытие лончера.
Singleton {
    id: root

    // Что открыть в лончере при следующем показе (например, после пипетки)
    property string launcherPreset: ""

    function copy(text) {
        Quickshell.execDetached(["wl-copy", "--", text])
    }

    function open(path) {
        Quickshell.execDetached(["xdg-open", path])
    }

    // Пипетка niri: курсор-прицел по всему экрану, потом снова лончер
    // с выбранным цветом в колесе
    function pickColor() {
        picker.running = true
    }

    Process {
        id: picker
        command: ["niri", "msg", "pick-color"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = this.text.match(/#[0-9a-fA-F]{6}/)
                if (!m)
                    return
                root.copy(m[0])
                root.launcherPreset = "color:" + m[0]
                Ui.popoutRequested("launcher")
            }
        }
    }
}
