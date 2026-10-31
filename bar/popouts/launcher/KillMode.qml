import QtQuick
import Quickshell
import Quickshell.Io
import "../../../config"
import "../../../services"
import "Match.js" as Match

// «kill …» — процессы по загрузке CPU: TERM или KILL
Item {
    id: mode

    required property var launcher

    property var procs: []

    Process {
        id: psProc
        command: ["ps", "-eo", "pid=,pcpu=,rss=,comm=,args=", "--sort=-pcpu"]
        stdout: StdioCollector {
            onStreamFinished: {
                mode.procs = this.text.split("\n").map(l => l.trim().match(/^(\d+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(.*)$/))
                    .filter(m => m)
                    .map(m => ({ pid: m[1], cpu: m[2], mem: Number(m[3]) / 1024, comm: m[4], args: m[5] }))
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: mode.launcher.mode === "kill"
        triggeredOnStart: true
        onTriggered: psProc.running = true
    }

    // Ctrl+⏎: процесс — в htop, только он
    function handoff(pid) {
        const t = LauncherState.tui("htop", ["-p", pid])
        return { app: t.app, run: () => Zsh.runInTerminal(t.cmd) }
    }

    function items() {
        return Match.filterBy(procs, launcher.arg, p => [p.comm, p.args]).slice(0, 100).map(p => ({
            glyph: "󰆴",
            glyphColor: Number(p.cpu) > 50 ? Theme.red : Theme.overlay2,
            title: p.comm,
            sub: p.pid + "   ·   " + p.cpu + "% CPU   ·   " + p.mem.toFixed(0) + " МБ   ·   " + p.args,
            badge: "⏎ TERM   ⇧⏎ KILL",
            ghostSource: p.comm,
            handoff: mode.handoff(p.pid),
            run: shift => {
                Quickshell.execDetached(["kill", shift ? "-KILL" : "-TERM", p.pid])
                psProc.running = true
            }
        }))
    }
}
