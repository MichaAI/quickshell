import QtQuick
import Quickshell
import Quickshell.Io
import "../../../config"
import "../../../services"

// «~» — поиск файлов в домашней папке через fd;
// «~/» и «/» — обзор по пути: каталог до последнего "/", дальше — фильтр
Item {
    id: mode

    required property var launcher

    readonly property string home: Quickshell.env("HOME")

    function tilde(p) {
        return p.startsWith(home + "/") ? "~" + p.slice(home.length) : p
    }
    function expand(p) {
        return p.startsWith("~") ? home + p.slice(1) : p
    }

    function glyph(name, isDir) {
        if (isDir) return ""
        const ext = (name.match(/\.([^.\/]+)$/)?.[1] ?? "").toLowerCase()
        const map = {
            png: "󰋩", jpg: "󰋩", jpeg: "󰋩", webp: "󰋩", gif: "󰋩", svg: "󰜡",
            mp4: "󰕧", mkv: "󰕧", webm: "󰕧", mov: "󰕧",
            mp3: "󰎆", flac: "󰎆", ogg: "󰎆", wav: "󰎆", opus: "󰎆",
            pdf: "󰈦", txt: "󰈙", md: "󰍔", doc: "󰈬", docx: "󰈬", odt: "󰈬",
            xls: "󰈛", xlsx: "󰈛", csv: "󰈛", zip: "󰗄", tar: "󰗄", gz: "󰗄", xz: "󰗄", "7z": "󰗄",
            nix: "󱄅", qml: "󰫾", js: "󰌞", ts: "󰛦", py: "󰌠", rs: "󱘗", go: "󰟓",
            c: "󰙱", cpp: "󰙲", h: "󰙱", sh: "", zsh: "", json: "󰘦", toml: "󰘦", yaml: "󰘦", yml: "󰘦"
        }
        return map[ext] ?? "󰈔"
    }

    function item(full, isDir) {
        const name = full.replace(/\/$/, "").split("/").pop()
        return {
            glyph: glyph(name, isDir),
            glyphColor: isDir ? Theme.sapphire : Theme.overlay2,
            title: name + (isDir ? "/" : ""),
            sub: tilde(full.replace(/\/$/, "")),
            badge: isDir ? "⏎ открыть   Tab войти" : "⏎ открыть   ⇧⏎ папку",
            run: shift => {
                const p = full.replace(/\/$/, "")
                Tools.open(shift && !isDir ? p.slice(0, p.lastIndexOf("/")) || "/" : p)
                Ui.closePopouts()
            },
            tab: () => launcher.setQuery(tilde(full.replace(/\/$/, "")) + (isDir ? "/" : ""))
        }
    }

    // ===== Поиск через fd =====

    property var fdResults: []
    property string fdFor: ""
    Process {
        id: fdProc
        property string forQuery: ""
        stdout: StdioCollector {
            onStreamFinished: {
                mode.fdResults = this.text.split("\n").filter(l => l !== "")
                mode.fdFor = fdProc.forQuery
            }
        }
    }

    function request() {
        const arg = launcher.arg
        if (arg.length < 2) {
            fdResults = []
            fdFor = arg
            return
        }
        fdProc.running = false
        fdProc.forQuery = arg
        fdProc.command = ["fd", "--ignore-case", "--fixed-strings", "--max-results", "80",
            "--color", "never", "--absolute-path", "--", arg, home]
        fdProc.running = true
    }

    function filesItems() {
        if (launcher.arg.length < 2)
            return [{ glyph: "󰈞", glyphColor: Theme.overlay1, title: "Начни вводить имя файла",
                sub: "Поиск через fd по домашней папке; ~/ или / — обзор по пути", run: () => {} }]
        return fdResults.map(p => item(p, p.endsWith("/")))
    }

    // ===== Обзор по пути =====

    property var dirEntries: []
    property string dirFor: ""
    Process {
        id: lsProc
        property string forDir: ""
        stdout: StdioCollector {
            onStreamFinished: {
                mode.dirEntries = this.text.split("\n").filter(l => l !== "" && l !== "./" && l !== "../")
                mode.dirFor = lsProc.forDir
            }
        }
    }

    readonly property string pathDir: launcher.mode === "path"
        ? launcher.arg.slice(0, launcher.arg.lastIndexOf("/") + 1) : ""
    readonly property string pathRest: launcher.mode === "path"
        ? launcher.arg.slice(launcher.arg.lastIndexOf("/") + 1) : ""

    onPathDirChanged: {
        if (pathDir === "" || pathDir === dirFor) return
        lsProc.running = false
        lsProc.forDir = pathDir
        lsProc.command = ["ls", "-1Ap", "--color=never", "--", expand(pathDir)]
        lsProc.running = true
    }

    function pathItems() {
        if (dirFor !== pathDir) return []
        const rest = pathRest.toLowerCase()
        const hidden = rest.startsWith(".")
        const list = dirEntries.filter(e => hidden || !e.startsWith("."))
        const starts = list.filter(e => e.toLowerCase().startsWith(rest))
        const contains = rest === "" ? [] : list.filter(e => !e.toLowerCase().startsWith(rest) && e.toLowerCase().includes(rest))
        return [...starts, ...contains].slice(0, 200).map(e => {
            const isDir = e.endsWith("/")
            const it = item(expand(pathDir) + e, isDir)
            it.ghostSource = e
            if (isDir) {
                it.run = shift => {
                    if (shift) { Tools.open(expand(pathDir) + e); Ui.closePopouts() }
                    else launcher.setQuery(pathDir + e)
                }
                it.badge = "⏎ войти   ⇧⏎ открыть"
            }
            return it
        })
    }

    function pathGhost() {
        const r = pathRest
        const e = launcher.results.find(it => it.ghostSource?.toLowerCase().startsWith(r.toLowerCase()))
        return e && r !== "" ? e.ghostSource.slice(r.length) : ""
    }
}
