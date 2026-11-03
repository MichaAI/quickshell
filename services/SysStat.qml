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

    // Прошлые счётчики — для скоростей: у каждого файла свои
    property var _prevCpu: null
    property var _prevNet: null
    property var _prevIo: null

    // Сколько попаутов показывают статистику: диск (df — процесс) меряем
    // только для них, остальное — чтение /proc в самом шелле, без процессов
    property int viewers: 0
    onViewersChanged: if (viewers > 0) df.running = true

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

    // Скорость по двум замерам: { v, t } → в секунду
    function _rate(prev, cur, key) {
        const dt = (cur.t - prev.t) / 1000
        return dt > 0 ? Math.max(0, (cur[key] - prev[key]) / dt) : 0
    }

    function _cpu(text) {
        const f = text.slice(0, text.indexOf("\n")).trim().split(/\s+/).slice(1).map(Number)
        const cur = { idle: f[3] + (f[4] || 0), total: f.reduce((a, b) => a + b, 0) }
        const p = _prevCpu
        if (p) {
            const dTotal = cur.total - p.total
            root.cpu = dTotal > 0 ? (1 - (cur.idle - p.idle) / dTotal) * 100 : 0
            root.cpuHist = _push(root.cpuHist, root.cpu / 100)
        }
        _prevCpu = cur
    }

    function _mem(text) {
        const mem = {}
        for (const line of text.split("\n")) {
            const m = line.match(/^(MemTotal|MemAvailable|SwapTotal|SwapFree):\s+(\d+)/)
            if (m) mem[m[1]] = Number(m[2]) * 1024
        }
        root.memTotal = (mem.MemTotal ?? 0) / 1073741824
        root.memUsed = ((mem.MemTotal ?? 0) - (mem.MemAvailable ?? 0)) / 1073741824
        root.memPerc = mem.MemTotal ? (1 - mem.MemAvailable / mem.MemTotal) * 100 : 0
        root.swapTotal = (mem.SwapTotal ?? 0) / 1073741824
        root.swapUsed = ((mem.SwapTotal ?? 0) - (mem.SwapFree ?? 0)) / 1073741824
        root.swapPerc = mem.SwapTotal ? (1 - mem.SwapFree / mem.SwapTotal) * 100 : 0
    }

    function _net(text) {
        const cur = { t: Date.now(), rx: 0, tx: 0 }
        for (const line of text.split("\n").slice(2)) {
            const parts = line.trim().split(/[:\s]+/)
            if (parts[0] === "lo" || parts.length < 10) continue
            cur.rx += Number(parts[1])
            cur.tx += Number(parts[9])
        }
        const p = _prevNet
        if (p) {
            root.netRx = _rate(p, cur, "rx")
            root.netTx = _rate(p, cur, "tx")
            root.netRxHist = _push(root.netRxHist, root.netRx)
            root.netTxHist = _push(root.netTxHist, root.netTx)
        }
        _prevNet = cur
    }

    function _io(text) {
        const cur = { t: Date.now(), rd: 0, wr: 0 }
        for (const line of text.split("\n")) {
            const f = line.trim().split(/\s+/)
            if (!/^(nvme\d+n\d+|sd[a-z]+|vd[a-z]+|mmcblk\d+)$/.test(f[2])) continue
            cur.rd += Number(f[5]) * 512
            cur.wr += Number(f[9]) * 512
        }
        const p = _prevIo
        if (p) {
            root.ioRead = _rate(p, cur, "rd")
            root.ioWrite = _rate(p, cur, "wr")
        }
        _prevIo = cur
    }

    // Файлы читаются асинхронно, каждый разбирается в своём onLoaded
    FileView { id: statFile; path: "/proc/stat"; onLoaded: root._cpu(text()) }
    FileView { id: memFile; path: "/proc/meminfo"; onLoaded: root._mem(text()) }
    FileView { id: netFile; path: "/proc/net/dev"; onLoaded: root._net(text()) }
    FileView { id: ioFile; path: "/proc/diskstats"; onLoaded: root._io(text()) }
    FileView {
        id: tempFile
        path: root.tempPath
        printErrors: false
        onLoaded: root.temp = Number(text()) / 1000
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload()
            memFile.reload()
            netFile.reload()
            ioFile.reload()
            if (root.tempPath !== "")
                tempFile.reload()
        }
    }

    // Датчик CPU (coretemp) ищем один раз: номера hwmon от загрузки к
    // загрузке разные
    property string tempPath: ""
    Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/*; do [ \"$(cat $h/name 2>/dev/null)\" = coretemp ] && echo $h/temp1_input && break; done"]
        stdout: StdioCollector {
            onStreamFinished: root.tempPath = this.text.trim()
        }
    }

    // Занятость диска меняется медленно: при открытии попаута и раз в
    // полминуты, пока он открыт
    Process {
        id: df
        running: true
        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = this.text.trim().split("\n")
                const f = rows[rows.length - 1].trim().split(/\s+/).map(Number)
                if (f.length < 2 || isNaN(f[1])) return
                root.diskUsed = f[0] / 1073741824
                root.diskTotal = f[1] / 1073741824
                root.diskPerc = f[1] ? f[0] / f[1] * 100 : 0
            }
        }
    }
    Timer {
        interval: 30000
        running: root.viewers > 0
        repeat: true
        onTriggered: df.running = true
    }
}
