import QtQuick
import Quickshell
import Quickshell.Io
import "../../../config"
import "../../../services"

// «#» — история буфера обмена (cliphist); «#rrggbb» ещё и цвет
Item {
    id: mode

    required property var launcher

    property var lines: []

    function refresh() {
        list.running = true
    }

    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: mode.lines = this.text.split("\n").filter(l => l !== "")
        }
    }

    function items() {
        const arg = launcher.arg
        const lq = arg.toLowerCase()
        const out = launcher.colorItem(arg.length >= 3 ? "#" + arg : "")
        let n = 0
        for (const line of lines) {
            if (n >= 100) break
            const tab = line.indexOf("\t")
            const preview = line.slice(tab + 1)
            if (lq !== "" && !preview.toLowerCase().includes(lq)) continue
            n++
            const img = preview.match(/^\[\[ binary data .* (png|jpe?g|webp|gif|bmp) (\d+x\d+) \]\]$/)
            out.push({
                glyph: img ? "󰋩" : "󰅍",
                glyphColor: Theme.yellow,
                clipImage: img ? line : "",
                clipExt: img ? img[1] : "",
                title: img ? "Картинка " + img[2] : preview.replace(/\s+/g, " ").slice(0, 200),
                sub: img ? preview.replace(/^\[\[ binary data /, "").replace(/ \]\]$/, "") : "",
                badge: "⏎ копировать   ⇧Del удалить",
                run: () => {
                    Tools.launch(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "qs", line], "wl-copy")
                    Ui.closePopouts()
                },
                del: () => {
                    Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist delete', "qs", line])
                    mode.lines = mode.lines.filter(l => l !== line)
                }
            })
        }
        return out
    }
}
