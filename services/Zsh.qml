pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// Шелл для лончера:
//  • автодополнение — живой zsh в zpty с твоим .zshrc (assets/launcher/zsh-complete.zsh);
//  • история из $HISTFILE — для «призрачных» подсказок;
//  • запуск команд в фоне в псевдотерминале. Если программа полезла на
//    альтернативный экран (vim, htop, less…) — роняем её и шлём уведомление.
Singleton {
    id: root

    property var history: []          // свежие первыми
    property var jobs: []             // [{id, cmd, proc, output, started}]
    property bool ready: false

    property int _seq: 0
    property var _pending: ({})       // id -> {callback, items}
    property var _histAcc: []

    // ===== Автодополнение =====

    function start() {
        if (!server.running)
            server.running = true
    }

    // callback([{word, desc}]) — дополнения для текущего слова буфера
    function complete(buffer, callback) {
        start()
        if (!ready) {
            callback([])
            return -1
        }
        const id = ++_seq
        _pending[id] = { callback, items: [] }
        server.write("C" + id + "\t" + buffer.replace(/[\r\n\t]/g, " ") + "\n")
        return id
    }

    function refreshHistory() {
        start()
        if (ready)
            server.write("H\n")
    }

    // Подсказка из истории: самая свежая команда, начинающаяся с prefix
    function suggest(prefix) {
        if (prefix.trim() === "")
            return ""
        for (const h of history)
            if (h.length > prefix.length && h.startsWith(prefix) && !h.includes("\\n"))
                return h
        return ""
    }

    function _onLine(line) {
        const parts = line.split("\t")
        if (parts[0] === "H") {
            if (parts[1] === "E" && parts.length === 2) {
                // Без повторов, порядок «свежие первыми» сохраняется
                root.history = [...new Set(_histAcc)]
                _histAcc = []
            } else {
                _histAcc.push(parts.slice(1).join("\t"))
            }
            return
        }
        const p = _pending[parts[0]]
        if (!p)
            return
        if (parts[1] === "M") {
            p.items.push({ word: parts[2] ?? "", desc: parts.slice(3).join("\t") })
        } else if (parts[1] === "E") {
            delete _pending[parts[0]]
            p.callback(p.items)
        }
    }

    Process {
        id: server
        command: ["zsh", Quickshell.shellPath("assets/launcher/zsh-complete.zsh")]
        workingDirectory: Quickshell.env("HOME")
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root._onLine(data)
        }
        // Запросы, пришедшие до конца загрузки .zshrc, просто подождут в stdin
        onStarted: {
            root.ready = true
            root.refreshHistory()
        }
        onExited: {
            root.ready = false
            for (const id of Object.keys(root._pending))
                root._pending[id].callback([])
            root._pending = {}
        }
    }

    // ===== Запуск =====

    function _quote(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'"
    }

    function stripAnsi(s) {
        return s.replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, "")
            .replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "")
            .replace(/\x1b[()][0-9A-Za-z]/g, "")
            .replace(/\x1b[=>78]/g, "")
            .replace(/\r\n/g, "\n")
            .replace(/[^\n\r]*\r(?!\n)/g, "")   // перерисованные строки (прогресс-бары)
            .replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "")
    }

    // Фоновый запуск в pty (script из util-linux): программа думает, что она
    // в терминале — значит, честно покажет альтернативный экран, если он ей нужен.
    // Задача — сам объект Process (cmd, output, altScreen, killed, started).
    function run(cmd) {
        const job = jobComp.createObject(root, { cmd: cmd, started: Date.now() })
        jobs = [...jobs, job]
        job.running = true
        return job
    }

    // В терминале — для всего интерактивного
    function runInTerminal(cmd) {
        Quickshell.execDetached([...Settings.terminal, "zsh", "-ic", cmd + "; exec zsh"])
    }

    function kill(job, force) {
        if (!job || !job.running)
            return
        if (!job.altScreen)
            job.killed = true
        killer.exec(["sh", "-c",
            'sid=$(ps -o sid= --ppid "$1" | head -1 | tr -d " "); ' +
            '[ -n "$sid" ] && pkill -' + (force ? "KILL" : "HUP") + ' -s "$sid"; ' +
            'kill -' + (force ? "KILL" : "TERM") + ' "$1" 2>/dev/null; ' +
            '[ -n "$sid" ] && { sleep 0.3; pkill -KILL -s "$sid"; }; true',
            "qs", job.processId.toString()])
    }

    function _finish(job, code) {
        jobs = jobs.filter(j => j !== job)
        const out = stripAnsi(job.output).replace(/Session terminated, killing shell\.\.\./g, "")
        const tail = out.split("\n").map(l => l.replace(/\s+$/, "")).filter(l => l !== "").slice(-6).join("\n")
        const secs = ((Date.now() - job.started) / 1000).toFixed(1)
        if (job.altScreen) {
            notify("normal", " Нужен терминал", job.cmd
                + "\nПрограмма открыла полноэкранный режим — запусти через Shift+Enter")
        } else if (job.killed) {
            notify("low", "󰅙 Остановлено", job.cmd)
        } else if (code === 0) {
            notify("low", " " + job.cmd, (tail || "Готово") + "\n— " + secs + " с")
        } else {
            notify("normal", " Код " + code + ": " + job.cmd, tail || "Без вывода")
        }
        job.destroy()
    }

    function notify(urgency, title, body) {
        notifier.exec(["notify-send", "-a", "Лончер", "-u", urgency, "-i", "utilities-terminal",
            title, body.replace(/&/g, "&amp;").replace(/</g, "&lt;")])
    }

    Process { id: killer }
    Process { id: notifier }

    Component {
        id: jobComp

        Process {
            id: p
            property string cmd
            property string output: ""
            property bool altScreen: false
            property bool killed: false
            property real started: 0

            command: ["script", "-qfec",
                "stty cols 120 rows 40 2>/dev/null; exec zsh -ic " + root._quote(cmd),
                "/dev/null"]
            environment: ({ SHELL: "/bin/sh", TERM: "xterm-256color" })
            workingDirectory: Quickshell.env("HOME")
            stdout: SplitParser {
                splitMarker: ""
                onRead: data => {
                    if (p.altScreen)
                        return
                    p.output = (p.output + data).slice(-16384)
                    if (/\x1b\[\?(1049|1047|47)h/.test(p.output.slice(-data.length - 16))) {
                        p.altScreen = true
                        root.kill(p, true)
                    }
                }
            }
            onExited: (code, _status) => root._finish(p, code)
        }
    }
}
