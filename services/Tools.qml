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

    // ===== Запуск того, что должно пережить шелл =====
    // Сервис systemd quickshell при остановке убивает всю свою cgroup, а в
    // ней — всё, что шелл запустил: рестарт шелла забирал с собой браузер.
    // systemd-run --scope выносит процесс в свою scope в app.slice, как
    // делают лончеры окружений рабочего стола. Дети процесса (вкладки
    // браузера и прочее) рождаются в той же scope и живут вместе с ней.
    // Без пользовательского systemd просто запускаем как есть
    readonly property string scopeScript: `
        name=$1; shift
        if command -v systemd-run >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
            exec systemd-run --user --scope --quiet --collect --slice=app.slice \
                --unit="app-quickshell-$(systemd-escape -- "$name")-$$.scope" -- "$@"
        fi
        exec "$@"`

    // name — для имени scope (id приложения), по умолчанию — сама программа
    function launch(command, name, workingDirectory) {
        Quickshell.execDetached({
            command: ["sh", "-c", root.scopeScript, "qs",
                      name || command[0].split("/").pop(), ...command],
            workingDirectory: workingDirectory ?? ""
        })
    }

    // wl-copy остаётся жить и раздаёт буфер обмена — тоже в свою scope,
    // иначе рестарт шелла стирал бы скопированное
    function copy(text) {
        launch(["wl-copy", "--", text])
    }

    function open(path) {
        launch(["xdg-open", path])
    }

    // Пипетка композитора (есть у niri): курсор-прицел по всему экрану,
    // потом снова лончер с выбранным цветом в колесе
    function pickColor() {
        if (Compositor.canPickColor)
            picker.running = true
    }

    Process {
        id: picker
        command: Compositor.pickColorCommand
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
