import QtQuick
import "../../../config"
import "../../../services"
import "Match.js" as Match

// «docker …» — контейнеры: запущенные сверху, обновление раз в 2 с.
// ⏎ — шелл в запущенном / запустить остановленный, Tab — все действия.
Item {
    id: mode

    required property var launcher

    // {list, error} — последнее, что сказал docker; переживает закрытие
    readonly property var info: LauncherState.cache.docker ?? { list: [], error: "" }

    function refresh() {
        Tools.run(["docker", "ps", "-a", "--no-trunc", "--format", "{{json .}}"], (code, out, err) => {
            if (!mode) return
            if (code !== 0) {
                LauncherState.put("docker", { list: mode.info.list,
                    error: code === 127 ? "docker не найден" : err.trim().split("\n").pop() })
                return
            }
            const list = out.split("\n").filter(l => l.trim() !== "").map(l => {
                try { return JSON.parse(l) } catch (e) { return null }
            }).filter(c => c).map(c => ({
                id: c.ID.slice(0, 12),
                name: c.Names,
                image: c.Image,
                state: c.State,
                status: c.Status,
                ports: (c.Ports ?? "").split(", ").filter(p => p !== "" && !p.startsWith("[::]")).join(", "),
                project: (c.Labels ?? "").match(/com\.docker\.compose\.project=([^,]+)/)?.[1] ?? ""
            }))
            const rank = s => s === "running" ? 0 : s === "paused" || s === "restarting" ? 1 : 2
            list.sort((a, b) => rank(a.state) - rank(b.state) || a.name.localeCompare(b.name))
            LauncherState.put("docker", { list, error: "" })
        })
    }

    Timer {
        interval: 2000
        repeat: true
        running: mode.launcher.mode === "docker"
        triggeredOnStart: true
        onTriggered: mode.refresh()
    }

    // Действие в фоне; ошибка — уведомлением
    function op(args, what) {
        Tools.run(["docker", ...args], (code, _o, err) => {
            if (code !== 0) Zsh.notify("normal", "docker: " + what, err.trim())
            if (mode) mode.refresh()
        })
    }

    function term(cmd) {
        Zsh.runInTerminal(cmd)
        Ui.closePopouts()
    }

    function shellCmd(c) {
        return "docker exec -it " + c.name + " sh -c 'command -v bash >/dev/null && exec bash || exec sh'"
    }

    function actions(c) {
        const running = c.state === "running"
        const list = []
        const add = (glyph, title, sub, fn, extra) => list.push(Object.assign({
            glyph, glyphColor: Theme.blue, title, sub, ghostSource: title, run: fn }, extra ?? {}))
        if (running) {
            add("󰆍", "Шелл", "docker exec -it … bash/sh", () => term(shellCmd(c)))
            add("󰦪", "Логи", "docker logs -f --tail 200", () => term("docker logs -f --tail 200 " + c.name))
            add("󰓛", "Остановить", "docker stop", () => { op(["stop", c.name], "stop"); launcher.back() })
            add("󰑓", "Перезапустить", "docker restart", () => { op(["restart", c.name], "restart"); launcher.back() })
            add("󰏤", "Пауза", "docker pause", () => { op(["pause", c.name], "pause"); launcher.back() })
        } else {
            add("󰐊", c.state === "paused" ? "Продолжить" : "Запустить", c.state === "paused" ? "docker unpause" : "docker start",
                () => { op([c.state === "paused" ? "unpause" : "start", c.name], "start"); launcher.back() })
            add("󰦪", "Логи", "docker logs --tail 200", () => term("docker logs --tail 200 " + c.name + " | less -R +G"))
        }
        add("󰈈", "Inspect", "docker inspect в терминале", () => term("docker inspect " + c.name + " | less"))
        add("󰆏", "Копировать ID", c.id, () => { Tools.copy(c.id); Ui.closePopouts() })
        const k = "docker-rm:" + c.id
        add("󰆴", "Удалить", launcher.confirmKey === k ? "Нажми Enter ещё раз, чтобы удалить" : "docker rm -f",
            () => {
                if (!launcher.confirmed(k)) return
                op(["rm", "-f", c.name], "rm")
                launcher.back()
            },
            { glyphColor: Theme.red, subColor: launcher.confirmKey === k ? Theme.red : undefined })
        return list
    }

    // Ctrl+⏎: lazydocker (своего нет — через nix run)
    function handoff() {
        const t = LauncherState.tui("lazydocker")
        return { app: t.app, run: () => Zsh.runInTerminal(t.cmd) }
    }

    function items() {
        const out = []
        if (info.error !== "")
            out.push({ glyph: "󰡨", glyphColor: Theme.red, title: info.error, sub: "docker ps", run: () => {} })
        const colors = { running: Theme.green, paused: Theme.yellow, restarting: Theme.yellow }
        for (const c of Match.filterBy(info.list, launcher.arg, c => [c.name, c.image, c.project])) {
            const running = c.state === "running"
            out.push({
                glyph: "󰡨",
                glyphColor: colors[c.state] ?? Theme.overlay0,
                title: c.name,
                sub: [c.image, c.status, c.ports, c.project ? "compose: " + c.project : ""].filter(s => s).join("   ·   "),
                badge: (running ? "⏎ шелл" : "⏎ запустить") + "   Tab действия",
                ghostSource: c.name,
                run: () => {
                    if (running) term(shellCmd(c))
                    else op([c.state === "paused" ? "unpause" : "start", c.name], "start")
                },
                tab: () => launcher.openMenu("󰡨", c.name, () => mode.actions(c))
            })
        }
        if (out.length === 0)
            out.push({ glyph: "󰡨", glyphColor: Theme.overlay1,
                       title: info.list.length ? "Нет совпадений" : "Контейнеров нет", run: () => {} })
        return out
    }
}
