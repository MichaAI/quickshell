pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Эквалайзер cava. Запускается при первом показе; когда смотреть
// некому, ещё немного работает (быстро открыли снова — без повторного
// старта) и завершается. Не замораживать (SIGSTOP): cava — клиент
// PipeWire, замёрзший клиент не читает свой сокет, у PipeWire копится
// очередь к нему, и при всплеске событий (подключили наушники) встаёт
// весь звук.
Singleton {
    id: root

    property var bars: []

    // Сколько попаутов сейчас показывают эквалайзер
    property int viewers: 0
    readonly property bool active: viewers > 0

    onActiveChanged: {
        if (active) {
            linger.stop()
            proc.running = true
        } else {
            linger.restart()
        }
    }

    Timer {
        id: linger
        interval: 30000
        onTriggered: {
            proc.running = false
            root.bars = []
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
