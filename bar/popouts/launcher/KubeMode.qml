import QtQuick
import "../../../config"
import "../../../services"
import "Match.js" as Match

// «kube …» — поды всех неймспейсов текущего контекста, обновление раз в 3 с.
// ⏎ — логи, Tab — все действия. «kube @…» — контексты, ⏎ переключает.
Item {
    id: mode

    required property var launcher

    // {context, contexts, pods, error} — переживает закрытие
    readonly property var info: LauncherState.cache.kube ?? { context: "", contexts: [], pods: [], error: "" }
    readonly property bool contextsView: launcher.arg.startsWith("@")
    property bool busy: false

    function set(patch) {
        LauncherState.put("kube", Object.assign({}, info, patch))
    }

    function refresh() {
        if (busy) return
        busy = true
        Tools.run(["sh", "-c", "kubectl config current-context; echo; kubectl config get-contexts -o name"], (code, out) => {
            if (!mode) return
            const parts = out.split("\n\n")
            mode.set({ context: (parts[0] ?? "").trim(),
                       contexts: (parts[1] ?? "").split("\n").filter(l => l.trim() !== "") })
            if (mode.info.context === "") {
                mode.busy = false
                mode.set({ pods: [], error: code === 127 ? "kubectl не найден" : "Нет текущего контекста" })
                return
            }
            Tools.run(["kubectl", "get", "pods", "-A", "-o", "json", "--request-timeout=5s"], (code2, out2, err2) => {
                if (!mode) return
                mode.busy = false
                if (code2 !== 0) {
                    mode.set({ error: err2.trim().split("\n").pop() || "kubectl: код " + code2 })
                    return
                }
                try {
                    mode.set({ pods: JSON.parse(out2).items.map(mode.pod), error: "" })
                } catch (e) {
                    mode.set({ error: "Непонятный ответ kubectl: " + e })
                }
            })
        })
    }

    function pod(p) {
        const cs = p.status?.containerStatuses ?? []
        const waiting = cs.map(c => c.state?.waiting?.reason ?? c.state?.terminated?.reason).find(r => r)
        return {
            ns: p.metadata.namespace,
            name: p.metadata.name,
            phase: p.metadata.deletionTimestamp ? "Terminating" : waiting ?? p.status?.phase ?? "?",
            ready: cs.filter(c => c.ready).length + "/" + cs.length,
            restarts: cs.reduce((s, c) => s + (c.restartCount ?? 0), 0),
            node: p.spec?.nodeName ?? "",
            containers: (p.spec?.containers ?? []).map(c => c.name)
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: mode.launcher.mode === "kube"
        triggeredOnStart: true
        onTriggered: mode.refresh()
    }

    function term(cmd) {
        Zsh.runInTerminal(cmd)
        Ui.closePopouts()
    }

    function kc(p) {
        return "kubectl -n " + p.ns + " "
    }

    function actions(p) {
        const list = []
        const add = (glyph, title, sub, fn, extra) => list.push(Object.assign({
            glyph, glyphColor: Theme.blue, title, sub, ghostSource: title, run: fn }, extra ?? {}))
        add("󰦪", "Логи", "logs -f --all-containers", () => term(kc(p) + "logs -f --tail 200 --all-containers " + p.name))
        add("󰦪", "Логи прошлого запуска", "logs --previous", () => term(kc(p) + "logs --previous --all-containers " + p.name + " | less +G"))
        for (const c of p.containers)
            add("󰆍", "Шелл: " + c, "exec -it -c " + c,
                () => term(kc(p) + "exec -it " + p.name + " -c " + c + " -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'"))
        add("󰈈", "Describe", "describe pod", () => term(kc(p) + "describe pod " + p.name + " | less"))
        add("󰘦", "YAML", "get -o yaml", () => term(kc(p) + "get pod " + p.name + " -o yaml | less"))
        add("󰆏", "Копировать имя", p.ns + "/" + p.name, () => { Tools.copy(p.name); Ui.closePopouts() })
        const k = "kube-del:" + p.ns + "/" + p.name
        add("󰆴", "Удалить под", launcher.confirmKey === k ? "Нажми Enter ещё раз, чтобы удалить" : "delete pod",
            () => {
                if (!launcher.confirmed(k)) return
                Tools.run(["kubectl", "-n", p.ns, "delete", "pod", p.name, "--wait=false"], (code, _o, err) => {
                    if (code !== 0) Zsh.notify("normal", "kubectl delete", err.trim())
                    if (mode) mode.refresh()
                })
                launcher.back()
            },
            { glyphColor: Theme.red, subColor: launcher.confirmKey === k ? Theme.red : undefined })
        return list
    }

    // Ctrl+⏎: k9s — на подах неймспейса, в нужном контексте
    function handoff(args) {
        const t = LauncherState.tui("k9s", args ?? [])
        return { app: t.app, run: () => Zsh.runInTerminal(t.cmd) }
    }

    function contextItems() {
        return Match.filterBy(info.contexts, launcher.arg.slice(1).trim(), c => [c]).map(c => ({
            glyph: c === info.context ? "󰄬" : "󱃾",
            glyphColor: c === info.context ? Theme.green : Theme.blue,
            title: c,
            sub: c === info.context ? "текущий" : "",
            badge: "⏎ переключить",
            ghostSource: "@" + c,
            handoff: mode.handoff(["--context", c]),
            run: () => Tools.run(["kubectl", "config", "use-context", c], () => {
                if (!mode) return
                mode.set({ pods: [] })
                launcher.setQuery("kube ")
                mode.refresh()
            })
        }))
    }

    function items() {
        if (contextsView) return contextItems()
        const out = []
        if (info.error !== "")
            out.push({ glyph: "󱃾", glyphColor: Theme.red, title: info.error,
                       sub: info.context ? "контекст " + info.context + "   ·   kube @ — сменить" : "", run: () => {} })
        const color = ph => ph === "Running" || ph === "Succeeded" ? Theme.green
            : ph === "Pending" || ph === "ContainerCreating" || ph === "Terminating" ? Theme.yellow : Theme.red
        for (const p of Match.filterBy(info.pods, launcher.arg, p => [p.name, p.ns, p.phase]).slice(0, 200))
            out.push({
                glyph: "󱃾",
                glyphColor: color(p.phase),
                title: p.name,
                sub: [p.ns, p.phase, "готово " + p.ready, p.restarts ? "рестартов " + p.restarts : "", p.node]
                    .filter(s => s).join("   ·   "),
                badge: "⏎ логи   Tab действия",
                ghostSource: p.name,
                handoff: mode.handoff(["-n", p.ns, "-c", "pods"]),
                run: () => term(kc(p) + "logs -f --tail 200 --all-containers " + p.name),
                tab: () => launcher.openMenu("󱃾", p.ns + "/" + p.name, () => mode.actions(p))
            })
        if (out.length === 0)
            out.push({ glyph: "󱃾", glyphColor: Theme.overlay1,
                       title: info.context === "" ? "Загружаю…" : info.pods.length ? "Нет совпадений" : "Подов нет",
                       sub: info.context ? "контекст " + info.context + "   ·   kube @ — сменить" : "",
                       progress: info.context === "" && info.error === "" ? -1 : undefined, run: () => {} })
        return out
    }
}
