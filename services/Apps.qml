pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// Приложения для лончера. Поднимается при старте шелла (см. shell.qml):
// DesktopEntries сканирует .desktop при первом обращении — пусть это будет
// не на первом открытии лончера. Установку/удаление программ ловит сам.
Singleton {
    id: root

    readonly property var list: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)

    // Рейтинг: частота запусков (аналог кэша wofi), id → число
    property var counts: ({})
    readonly property string histFile: Quickshell.env("HOME") + "/.cache/quickshell-launcher-hist"

    function freq(app) {
        return root.counts[app.id] ?? 0
    }

    function launch(app, action) {
        histWrite.exec(["sh", "-c", 'printf "%s\\n" "$1" >> "$2"', "qs", app.id, root.histFile])
        counts = Object.assign({}, root.counts, { [app.id]: root.freq(app) + 1 })
        // Не app.execute(): так приложение осталось бы в cgroup шелла.
        // Terminal=true (htop, btop…) — сами заворачиваем в терминал; флаг
        // берём у app: у DesktopAction своего Terminal= нет.
        const cmd = (action ?? app).command
        Tools.launch(app.runInTerminal ? [...Settings.terminal, ...cmd] : cmd,
                     app.id, app.workingDirectory)
    }

    FileView {
        path: root.histFile
        printErrors: false
        onLoaded: {
            const c = {}
            for (const l of text().split("\n"))
                if (l !== "") c[l] = (c[l] ?? 0) + 1
            root.counts = c
        }
    }

    Process { id: histWrite }
}
