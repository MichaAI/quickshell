import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "Match.js" as Match

// «port …» — слушающие порты (ss -tulpn) и процессы на них, раз в 2 с.
// Процессы других пользователей ss без root не показывает — для портов
// докера подписывается контейнер, если docker-режим его уже видел.
// ⏎ — открыть http://localhost:порт, ⇧⏎ — копировать, ⇧Del — TERM процессу.
Item {
    id: mode

    required property var launcher

    // [{proto, port, addrs, procs: [{name, pid}]}]
    readonly property var list: LauncherState.cache.ports ?? []
    property string error: ""

    function refresh() {
        Tools.run(["ss", "-H", "-tulpn"], (code, out, err) => {
            if (!mode) return
            if (code !== 0) {
                mode.error = code === 127 ? "ss не найден (пакет iproute2)" : err.trim()
                return
            }
            mode.error = ""
            const byKey = {}
            for (const l of out.split("\n")) {
                const f = l.trim().split(/\s+/)
                if (f.length < 5) continue
                const local = f[4]
                const i = local.lastIndexOf(":")
                const port = Number(local.slice(i + 1))
                if (!port) continue
                const addr = local.slice(0, i).replace(/%.*$/, "").replace(/^\[|\]$/g, "")
                const procs = mode.all(l, /\("([^"]+)",pid=(\d+)/g).map(m => ({ name: mode.clean(m[1]), pid: m[2] }))
                const k = f[0] + port + procs.map(p => p.pid).join(",")
                if (!byKey[k]) byKey[k] = { proto: f[0], port, addrs: [], procs }
                const e = byKey[k]
                if (!e.addrs.includes(addr)) e.addrs.push(addr)
            }
            LauncherState.put("ports", Object.values(byKey).sort((a, b) => a.port - b.port || a.proto.localeCompare(b.proto)))
        })
    }

    Timer {
        interval: 2000
        repeat: true
        running: mode.launcher.mode === "ports"
        triggeredOnStart: true
        onTriggered: mode.refresh()
    }

    // Обёртки nix: «.foo-wrapped», а ss ещё и режет имя до 15 символов
    function clean(n) {
        return n.replace(/^\./, "").replace(/-wr(a(p(p(e(d)?)?)?)?)?$/, "")
    }

    function all(s, re) {
        const out = []
        let m
        while ((m = re.exec(s)) !== null) out.push(m)
        return out
    }

    // Порт -> контейнеры, по последнему списку docker-режима
    function containers() {
        const m = {}
        for (const c of LauncherState.cache.docker?.list ?? [])
            for (const p of all(c.ports ?? "", /:(\d+)->/g))
                m[p[1]] = [...(m[p[1]] ?? []), c.name]
        return m
    }

    function items() {
        const dk = containers()
        const out = []
        if (error !== "")
            out.push({ glyph: "󰈀", glyphColor: Theme.red, title: error, run: () => {} })
        const local = a => a === "127.0.0.1" || a === "::1" || a.startsWith("127.")
        for (const e of Match.filterBy(list, launcher.arg,
                e => [String(e.port), ...e.procs.map(p => p.name), ...(dk[e.port] ?? [])])) {
            const who = e.procs.length ? e.procs.map(p => p.name).join(", ")
                : dk[e.port] ? "docker: " + dk[e.port].join(", ") : "чужой процесс"
            const pids = e.procs.map(p => p.pid)
            out.push({
                glyph: e.proto === "udp" ? "󰛳" : "󰈀",
                glyphColor: e.addrs.every(local) ? Theme.overlay2 : e.procs.length ? Theme.sapphire : Theme.yellow,
                title: ":" + e.port + "   " + who,
                sub: [e.proto, e.addrs.map(a => a === "0.0.0.0" || a === "::" || a === "*" ? "все адреса" : a).filter((a, i, s) => s.indexOf(a) === i).join(", "),
                      pids.length ? "pid " + pids.join(", ") : ""].filter(s => s).join("   ·   "),
                badge: (e.proto === "tcp" ? "⏎ открыть   " : "") + "⇧⏎ копировать" + (pids.length ? "   ⇧Del TERM" : ""),
                ghostSource: String(e.port),
                handoff: pids.length ? (() => {
                    const t = LauncherState.tui("htop", pids.reduce((a, p) => [...a, "-p", p], []))
                    return { app: t.app, run: () => Zsh.runInTerminal(t.cmd) }
                })() : undefined,
                run: shift => {
                    if (shift || e.proto !== "tcp") Tools.copy("localhost:" + e.port)
                    else Tools.open("http://localhost:" + e.port)
                    Ui.closePopouts()
                },
                del: pids.length ? () => {
                    Quickshell.execDetached(["kill", "-TERM", ...pids])
                    mode.refresh()
                } : undefined
            })
        }
        return out
    }
}
