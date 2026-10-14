pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Эквалайзер cava. Запускается при первом показе и дальше не
// перезапускается: когда смотреть некому, процесс замораживается
// (SIGSTOP), при следующем показе размораживается (SIGCONT) — без
// повторного старта и сбора сэмплов.
Singleton {
    id: root

    property var bars: []

    // Сколько попаутов сейчас показывают эквалайзер
    property int viewers: 0
    readonly property bool active: viewers > 0

    readonly property int sigCont: 18
    readonly property int sigStop: 19

    onActiveChanged: {
        if (active) {
            if (proc.running)
                proc.signal(sigCont)
            else
                proc.running = true
        } else if (proc.running) {
            proc.signal(sigStop)
        }
    }

    Process {
        id: proc
        command: ["cava", "-p", Qt.resolvedUrl("../assets/cava.conf").toString().replace("file://", "")]

        stdout: SplitParser {
            onRead: line => {
                const vals = line.split(";").filter(s => s !== "").map(Number)
                if (vals.length > 0)
                    root.bars = vals
            }
        }
    }
}
