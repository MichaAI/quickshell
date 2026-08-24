pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Системная статистика: CPU, RAM, swap, температура, сеть, диск, IO.
Singleton {
    id: root

    property real cpu: 0          // %
    property real temp: 0         // °C
    property real memPerc: 0      // %
    property real memUsed: 0      // GiB
    property real memTotal: 0     // GiB
    property real swapPerc: 0
    property real swapUsed: 0
    property real swapTotal: 0
    property real netRx: 0        // B/s
    property real netTx: 0        // B/s
    property real ioRead: 0       // B/s
    property real ioWrite: 0      // B/s
    property real diskPerc: 0
    property real diskUsed: 0     // GiB
    property real diskTotal: 0    // GiB

    property var cpuHist: []
    property var netRxHist: []
    property var netTxHist: []

    property var _prev: null

    readonly property string script:
        "head -1 /proc/stat; echo @; " +
        "grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree)' /proc/meminfo; echo @; " +
        "cat /proc/net/dev; echo @; " +
        "cat /proc/diskstats; echo @; " +
        "for h in /sys/class/hwmon/*; do [ \"$(cat $h/name 2>/dev/null)\" = coretemp ] && cat $h/temp1_input; done; echo @; " +
        "df -B1 --output=used,size / 2>/dev/null | tail -1"

    function fmtBytes(b) {
        if (b < 1024) return b.toFixed(0) + " B"
        if (b < 1024 * 1024) return (b / 1024).toFixed(1) + " K"
        if (b < 1024 * 1024 * 1024) return (b / 1024 / 1024).toFixed(1) + " M"
        return (b / 1024 / 1024 / 1024).toFixed(2) + " G"
    }

    function _push(hist, v) {
        const h = hist.slice(-39)
        h.push(v)
        return h
    }

    function _parse(text) {
        const sections = [[]]
        for (const line of text.split("\n")) {
            if (line.trim() === "@")
                sections.push([])
            else if (line.length > 0)
                sections[sections.length - 1].push(line)
        }
        if (sections.length < 6)
            return

        const now = Date.now()
        const cur = { t: now }

        // --- CPU ---
        {
            const f = sections[0][0].trim().split(/\s+/).slice(1).map(Number)
            const idle = f[3] + (f[4] || 0)
            const total = f.reduce((a, b) => a + b, 0)
            cur.cpuIdle = idle
            cur.cpuTotal = total
        }

        // --- Память ---
        {
            const mem = {}
            for (const line of sections[1]) {
                const m = line.match(/^(\w+):\s+(\d+)/)
                if (m) mem[m[1]] = Number(m[2]) * 1024
            }
            root.memTotal = (mem.MemTotal ?? 0) / 1073741824
            root.memUsed = ((mem.MemTotal ?? 0) - (mem.MemAvailable ?? 0)) / 1073741824
            root.memPerc = mem.MemTotal ? (1 - mem.MemAvailable / mem.MemTotal) * 100 : 0
            root.swapTotal = (mem.SwapTotal ?? 0) / 1073741824
            root.swapUsed = ((mem.SwapTotal ?? 0) - (mem.SwapFree ?? 0)) / 1073741824
            root.swapPerc = mem.SwapTotal ? (1 - mem.SwapFree / mem.SwapTotal) * 100 : 0
        }

        // --- Сеть ---
        {
            let rx = 0, tx = 0
            for (const line of sections[2].slice(2)) {
                const parts = line.trim().split(/[:\s]+/)
                if (parts[0] === "lo" || parts.length < 10) continue
                rx += Number(parts[1])
                tx += Number(parts[9])
            }
            cur.rx = rx
            cur.tx = tx
        }

        // --- Диск IO ---
        {
            let rd = 0, wr = 0
            for (const line of sections[3]) {
                const f = line.trim().split(/\s+/)
                if (!/^(nvme\d+n\d+|sd[a-z]+|vd[a-z]+|mmcblk\d+)$/.test(f[2])) continue
                rd += Number(f[5]) * 512
                wr += Number(f[9]) * 512
            }
            cur.rd = rd
            cur.wr = wr
        }

        // --- Температура ---
        if (sections[4].length > 0)
            root.temp = Number(sections[4][0]) / 1000

        // --- Диск / ---
        if (sections[5].length > 0) {
            const f = sections[5][0].trim().split(/\s+/).map(Number)
            root.diskUsed = f[0] / 1073741824
            root.diskTotal = f[1] / 1073741824
            root.diskPerc = f[1] ? f[0] / f[1] * 100 : 0
        }

        // --- Дельты ---
        const p = root._prev
        if (p) {
            const dt = (now - p.t) / 1000
            const dTotal = cur.cpuTotal - p.cpuTotal
            const dIdle = cur.cpuIdle - p.cpuIdle
            root.cpu = dTotal > 0 ? (1 - dIdle / dTotal) * 100 : 0
            root.netRx = Math.max(0, (cur.rx - p.rx) / dt)
            root.netTx = Math.max(0, (cur.tx - p.tx) / dt)
            root.ioRead = Math.max(0, (cur.rd - p.rd) / dt)
            root.ioWrite = Math.max(0, (cur.wr - p.wr) / dt)

            root.cpuHist = _push(root.cpuHist, root.cpu / 100)
            root.netRxHist = _push(root.netRxHist, root.netRx)
            root.netTxHist = _push(root.netTxHist, root.netTx)
        }
        root._prev = cur
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Process {
        id: proc
        command: ["sh", "-c", root.script]

        stdout: StdioCollector {
            onStreamFinished: root._parse(this.text)
        }
    }
}
