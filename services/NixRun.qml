pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick

// Запуск программ из nixpkgs без установки (режим «,» лончера). Сначала
// nix build с машинным логом (--log-format internal-json) — из него виден
// прогресс скачивания, — потом программа прямо из стора: бинарник или
// Exec из .desktop. Закачка живёт здесь, а не в попауте: закрыл лончер —
// она продолжается, программа запустится сама. Пока лончер в режиме «,»
// открыт (viewers > 0), прогресс в нём; закрыт — в уведомлении (hint value).
//
// spec: { attr: "qrencode.bin", title, args: [],
//         bin: "qrencode" | desktop: "org.gimp.GIMP.desktop" | mainProgram: true,
//         terminal: bool }
Singleton {
    id: root

    property var jobs: []
    // Сколько открыто мест, где закачки и так видно (режим «,» лончера)
    property int viewers: 0

    // Программа запущена — лончер может закрыться
    signal launched(string key)

    function keyOf(spec) {
        return spec.attr + "/" + (spec.desktop || spec.bin || "") + " " + (spec.args ?? []).join(" ")
    }

    function run(spec) {
        const key = keyOf(spec)
        if (jobs.some(j => j.key === key)) return
        const j = jobComp.createObject(root, { spec, key })
        jobs = [...jobs, j]
        j.running = true
    }

    function cancel(j) {
        j.cancelled = true
        j.running = false
    }

    // «Скачиваю · 12.3 / 45.6 МиБ · 2/5 путей»
    function status(j) {
        const mib = b => (b / 1048576).toFixed(b < 10485760 ? 1 : 0)
        const sizes = j.expected > 0 ? mib(j.done) + " / " + mib(j.expected) + " МиБ"
            : j.done > 0 ? mib(j.done) + " МиБ" : ""
        const paths = j.pathsTotal > 0 ? j.paths + "/" + j.pathsTotal + " путей" : ""
        return [j.phase, sizes, paths].filter(x => x).join("   ·   ")
    }

    // Уведомление с прогрессом: пока режим «,» открыт — не нужно
    function _notify(j, final, summary, body, urgent) {
        if (!final && viewers > 0 && j.ns.id === 0) return
        Tools.notifyProgress(j.ns, summary, body,
            final || j.expected <= 0 ? null : j.done / j.expected * 100, final, urgent)
    }

    Timer {
        interval: 700
        repeat: true
        running: root.jobs.length > 0
        onTriggered: {
            for (const j of root.jobs)
                root._notify(j, false, "nix: " + j.spec.title, root.status(j))
        }
    }

    function _done(j) {
        jobs = jobs.filter(x => x !== j)
        j.destroy()
    }

    // ===== Запуск из стора =====

    function _launch(spec, paths) {
        const args = spec.args ?? []
        const key = keyOf(spec)
        if (spec.mainProgram) {
            // Пакет уже в сторе — nix run только вычислит и запустит
            const cmd = ["nix", "run", "nixpkgs#" + spec.attr, ...(args.length ? ["--", ...args] : [])]
            if (spec.terminal) Zsh.runInTerminal(cmd.map(Zsh._quote).join(" "))
            else Tools.launch(cmd, spec.attr)
            launched(key)
            return
        }
        if (spec.bin) {
            Tools.run(["sh", "-c", 'b=$1; shift; for p; do [ -e "$p/bin/$b" ] && { echo "$p/bin/$b"; exit; }; done; exit 1',
                       "sh", spec.bin, ...paths], (code, out) => {
                if (code !== 0) return Zsh.notify("normal", "nix: " + spec.bin, "В пакете нет bin/" + spec.bin)
                const exe = out.trim()
                if (spec.terminal) Zsh.runInTerminal([exe, ...args].map(Zsh._quote).join(" "))
                else Tools.launch([exe, ...args], spec.bin)
                root.launched(key)
            })
            return
        }
        // .desktop: найти файл в выходах пакета и запустить его Exec
        Tools.run(["sh", "-c", 'd=$1; shift; for p; do f=$p/share/applications/$d; [ -e "$f" ] && { echo "$p"; cat "$f"; exit; }; done; exit 1',
                   "sh", spec.desktop, ...paths], (code, out) => {
            if (code !== 0) return Zsh.notify("normal", "nix: " + spec.title, "В пакете нет " + spec.desktop)
            const nl = out.indexOf("\n")
            const pkg = out.slice(0, nl)
            const e = root.parseDesktop(out.slice(nl + 1))
            if (e.exec.length === 0) return Zsh.notify("normal", "nix: " + spec.title, "В " + spec.desktop + " нет Exec")
            // Exec часто — просто имя программы: ищем её в bin пакета
            const cmd = ["env", "PATH=" + pkg + "/bin:" + (Quickshell.env("PATH") ?? ""), ...e.exec, ...args]
            if (e.terminal) Zsh.runInTerminal(cmd.map(Zsh._quote).join(" "))
            else Tools.launch(cmd, spec.desktop.replace(/\.desktop$/, ""))
            root.launched(key)
        })
    }

    // Exec и Terminal из [Desktop Entry]; коды полей (%u, %F…) выкидываем
    function parseDesktop(text) {
        let inEntry = false
        let exec = ""
        let terminal = false
        for (const l of text.split("\n")) {
            if (/^\[.*\]$/.test(l.trim())) { inEntry = l.trim() === "[Desktop Entry]"; continue }
            if (!inEntry) continue
            const m = l.match(/^(Exec|Terminal)\s*=\s*(.*)$/)
            if (!m) continue
            if (m[1] === "Exec") exec = m[2]
            else terminal = m[2].trim() === "true"
        }
        const tokens = []
        const re = /"((?:[^"\\]|\\.)*)"|(\S+)/g
        let t
        while ((t = re.exec(exec)) !== null) {
            const w = t[1] !== undefined ? t[1].replace(/\\(.)/g, "$1") : t[2]
            if (/^%[fFuUdDnNickvm]$/.test(w)) continue
            tokens.push(w.replace(/%%/g, "%"))
        }
        return { exec: tokens, terminal }
    }

    // ===== Закачка =====

    Component {
        id: jobComp

        Process {
            id: job

            required property var spec
            required property string key
            property bool cancelled: false

            // Что показывать: фаза, байты скачанного (сжатого) и пути
            property string phase: "Вычисляю nixpkgs…"
            property real done: 0
            property real expected: 0
            property int paths: 0
            property int pathsTotal: 0
            property string lastError: ""
            property var ns: ({ id: 0, busy: false })

            property var acts: ({})       // id -> {type, nar}
            property var narDone: ({})    // id закачки nar -> байт
            property var expectedBy: ({}) // id -> ожидаемые байты

            command: ["nix", "build", "--no-link", "--print-out-paths", "--log-format", "internal-json",
                      "nixpkgs#" + spec.attr]

            function sum(o) {
                let s = 0
                for (const k in o) s += o[k]
                return s
            }

            function onLog(line) {
                if (!line.startsWith("@nix ")) return
                let e
                try { e = JSON.parse(line.slice(5)) } catch (err) { return }
                if (e.action === "start") {
                    acts[e.id] = { type: e.type, nar: e.type === 101 && /\/nar\//.test(e.fields?.[0] ?? "") }
                    if (e.type === 109) phase = "Ищу в кэше…"
                    else if (e.type === 100) phase = "Скачиваю"
                    else if (e.type === 105) phase = "Собираю: " + (e.text ?? "").replace(/^building '\/nix\/store\/[a-z0-9]+-/, "").replace(/\.drv'.*$/, "")
                } else if (e.action === "result") {
                    const a = acts[e.id]
                    if (e.type === 105 && a?.nar) {
                        narDone[e.id] = e.fields[0]
                        done = sum(narDone)
                    } else if (e.type === 105 && a?.type === 103) {
                        paths = e.fields[0]
                        pathsTotal = e.fields[1]
                    } else if (e.type === 106 && e.fields[0] === 101) {
                        expectedBy[e.id] = e.fields[1]
                        expected = sum(expectedBy)
                    }
                } else if (e.action === "msg" && e.level === 0) {
                    lastError = Zsh.stripAnsi(e.msg ?? "").trim()
                }
            }

            // Конец — когда и процесс вышел, и stdout дочитан
            property int left: 2
            property int code: -1

            function step() {
                if (--left > 0) return
                if (code === 0) {
                    if (ns.id) root._notify(job, true, "nix: " + spec.title, "Скачано, запускаю", false)
                    root._launch(spec, out.text.split("\n").filter(l => l !== ""))
                } else if (cancelled) {
                    if (ns.id) root._notify(job, true, "nix: " + spec.title, "Отменено", false)
                } else
                    root._notify(job, true, "nix: не вышло запустить " + spec.title,
                                 lastError.split("\n").slice(-3).join("\n") || "nix build: код " + code, true)
                root._done(job)
            }

            stdout: StdioCollector { id: out; onStreamFinished: job.step() }
            stderr: SplitParser { onRead: data => job.onLog(data) }
            onExited: (exitCode, _status) => { job.code = exitCode; job.step() }
        }
    }
}
