pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Мелкие системные действия, которые должны пережить закрытие лончера.
Singleton {
    id: root

    // Что открыть в лончере при следующем показе (например, после пипетки)
    property string launcherPreset: ""

    // ===== История запросов лончера (свежие первыми) =====

    readonly property string queriesFile: Quickshell.env("HOME") + "/.cache/quickshell-launcher-queries"
    readonly property int queriesMax: 500
    property var queries: []

    function addQuery(q) {
        if (q.trim() === "") return
        queries = [q, ...queries.filter(x => x !== q)].slice(0, queriesMax)
        _saveQueries()
    }

    function removeQuery(q) {
        queries = queries.filter(x => x !== q)
        _saveQueries()
    }

    function _saveQueries() {
        queriesView.setText(JSON.stringify(queries) + "\n")
    }

    FileView {
        id: queriesView
        path: root.queriesFile
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const v = JSON.parse(text())
                if (Array.isArray(v))
                    root.queries = v.filter(x => typeof x === "string")
            } catch (e) {}
        }
    }

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
