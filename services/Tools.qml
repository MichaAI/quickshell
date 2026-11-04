pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

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
    // иначе рестарт шелла стирал бы скопированное. Текст — через stdin:
    // аргументом больше 128 КБ (MAX_ARG_STRLEN) не пролезает, и копирование
    // молча не случалось. wl-copy дочитывает stdin, уходит в фон и выходит
    function copy(text) {
        const p = copyComp.createObject(root, {
            command: ["sh", "-c", root.scopeScript, "qs", "wl-copy", "wl-copy"], text
        })
        p.running = true
    }

    Component {
        id: copyComp

        Process {
            id: cp
            required property string text
            stdinEnabled: true
            onStarted: {
                cp.write(cp.text)
                cp.stdinEnabled = false     // EOF
            }
            onExited: cp.destroy()
        }
    }

    function open(path) {
        launch(["xdg-open", path])
    }

    // ===== Короткие команды с ответом =====
    // done(code, stdout, stderr) — когда процесс вышел и оба потока дочитаны.
    // Через sh: если программы нет, будет код 127, а не тишина
    function run(command, done) {
        const p = runComp.createObject(root, { command: ["sh", "-c", 'exec "$@"', "sh", ...command], done: done ?? null })
        p.running = true
        return p
    }

    Component {
        id: runComp

        Process {
            id: rp
            property var done: null
            property int code: -1
            property int left: 3

            function step() {
                if (--left > 0)
                    return
                const cb = done
                done = null
                if (cb)
                    cb(code, out.text, err.text)
                rp.destroy()
            }

            stdout: StdioCollector { id: out; onStreamFinished: rp.step() }
            stderr: StdioCollector { id: err; onStreamFinished: rp.step() }
            onExited: (exitCode, _status) => { rp.code = exitCode; rp.step() }
        }
    }

    // curl для сетевых режимов лончера: таймаут и прокси из Settings.netProxy
    function curl(args) {
        return ["curl", "-sfL", "--max-time", "15",
                ...(Settings.netProxy !== "" ? ["-x", Settings.netProxy] : []), ...args]
    }

    // ===== Уведомление с прогрессом =====
    // ns — {id, busy}, обычный объект хозяина: через него обновления
    // заменяют одно и то же уведомление (notify-send -r). value — 0…100
    // (полоса в карточке, hint value) или null. final — последнее
    // обновление: без полосы; не urgent — исчезнет через 3 с
    function notifyProgress(ns, summary, body, value, final, urgent) {
        if (ns.busy) {
            // Прошлый notify-send ещё не вернул id: промежуточное — пропустить,
            // последнее — дождаться, иначе оно выйдет отдельным уведомлением
            if (final) ns.queued = () => notifyProgress(ns, summary, body, value, final, urgent)
            return
        }
        const args = ["notify-send", "-p", "-a", "Лончер", "-u", urgent ? "normal" : "low"]
        if (ns.id) args.push("-r", String(ns.id))
        if (final && !urgent) args.push("-t", "3000", "-e")
        if (!final && value !== null) args.push("-h", "int:value:" + Math.round(value))
        args.push(summary, body)
        ns.busy = true
        run(args, (_code, out) => {
            ns.busy = false
            const id = parseInt(out)
            if (id > 0) ns.id = id
            const q = ns.queued
            ns.queued = null
            if (q) q()
        })
    }

    // ===== Скачать файл с прогрессом в уведомлении =====
    // Уже скачанный не качаем. Успех — done(file) и уведомление doneText,
    // неудача — уведомление об ошибке. Живёт здесь: попаут можно закрыть
    property var downloads: []

    function download(url, file, title, doneText, done) {
        const d = dlComp.createObject(root, { title, doneText, done: done ?? null,
            command: ["sh", "-c", 't=$1; shift; [ -s "$t" ] && exit 0; mkdir -p "${t%/*}" && "$@" -o "$t.part" && mv "$t.part" "$t"',
                      "sh", file, "curl", "-fL", "--max-time", "120",
                      ...(Settings.netProxy !== "" ? ["-x", Settings.netProxy] : []), url] })
        d.file = file
        downloads = [...downloads, d]
        d.running = true
    }

    Timer {
        interval: 700
        repeat: true
        running: root.downloads.length > 0
        onTriggered: {
            for (const d of root.downloads)
                if (d.pct >= 0)
                    root.notifyProgress(d.ns, d.title, "Скачиваю" + (d.total ? "   ·   " + d.total : ""), d.total ? d.pct : null, false, false)
        }
    }

    Component {
        id: dlComp

        Process {
            id: dl
            required property string title
            required property string doneText
            property var done: null
            property string file: ""
            property int pct: -1
            property string total: ""
            property var ns: ({ id: 0, busy: false })
            property string err: ""

            // Счётчик curl перерисовывается через \r: «45 3.2M 45 1.4M …»
            stderr: SplitParser {
                splitMarker: "\r"
                onRead: data => {
                    for (const line of data.split("\n")) {
                        const t = line.trim().split(/\s+/)
                        if (t.length >= 3 && /^\d+$/.test(t[0])) {
                            dl.pct = Number(t[0])
                            const u = { k: " КБ", M: " МБ", G: " ГБ" }
                            dl.total = t[1] === "0" ? "" : t[1].replace(/([kMG])$/, m => u[m]).replace(/^([\d.]+)$/, "$1 Б")
                        } else if (/^curl:/.test(line.trim()))
                            dl.err = line.trim()
                    }
                }
            }

            onExited: (code, _status) => {
                root.downloads = root.downloads.filter(x => x !== dl)
                if (code === 0) {
                    if (dl.done) dl.done(dl.file)
                    root.notifyProgress(dl.ns, dl.title, dl.doneText, null, true, false)
                } else
                    root.notifyProgress(dl.ns, dl.title + ": не скачалось", dl.err || "curl: код " + code, null, true, true)
                dl.destroy()
            }
        }
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
