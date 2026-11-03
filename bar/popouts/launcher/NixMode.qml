import QtQuick
import "../../../config"
import "../../../services"

// «,программа [аргументы]» — запуск без установки, как comma. В базе
// nix-index (nix-locate) ищутся и приложения (.desktop в share/applications),
// и бинарники; приложения — выше. Скачивает и запускает NixRun: пока
// качается, тут строка с прогрессом; закрыл лончер — запустится само.
// ⏎ — запустить (бинарник — в фоне), ⇧⏎ — в терминале, ⇧Del — отменить
// закачку. Пустой запрос — закачки и недавние.
Item {
    id: mode

    required property var launcher

    readonly property string word: launcher.arg.trim().split(/\s+/)[0] ?? ""
    readonly property string rest: launcher.arg.trim().slice(word.length).trim()
    readonly property var restArgs: rest === "" ? [] : rest.split(/\s+/)
    // {q, list: [{attr, out, bin | desktop, version}], error}
    readonly property var last: LauncherState.cache.nix ?? null
    property int token: 0

    // Пока режим открыт, прогресс виден здесь — уведомление не нужно
    Component.onCompleted: NixRun.viewers++
    Component.onDestruction: NixRun.viewers--

    // Запустилось — лончер больше не нужен
    Connections {
        target: NixRun
        function onLaunched() { Ui.closePopouts() }
    }

    function request() {
        const q = word
        if (q.length < 2 || last?.q === q) return
        const t = ++token
        const re = q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        // Два поиска разом: файл называется как запрос (бинарник или
        // .desktop) — и .desktop из пакетов, чьё имя похоже на запрос
        // (у gnome-mines он org.gnome.Mines.desktop)
        Tools.run(["sh", "-c", 'nix-locate --type x --type s --type r --color never --regex "$1" & '
                   + 'nix-locate --color never --regex -p "$2" "/share/applications/[^/]+\\.desktop$"; wait $!',
                   "sh",
                   "(?i)(/bin/([^/.][^/]*)?" + re + "[^/]*|/share/applications/[^/]*" + re + "[^/]*\\.desktop)$",
                   "(?i).*" + re + ".*"],
            (code, out, err) => {
            if (!mode || t !== mode.token) return
            if (code !== 0) {
                LauncherState.put("nix", { q, list: [],
                    error: code === 127 ? "nix-locate не найден (пакет nix-index)" : err.trim().split("\n").pop() })
                return
            }
            LauncherState.put("nix", { q, list: mode.parse(out, q), error: "" })
        })
    }

    function parse(out, q) {
        const seen = {}
        const list = []
        const lq = q.toLowerCase()
        for (const l of out.split("\n")) {
            const m = l.match(/^(\S+)\s+\S+\s+\S\s+\/nix\/store\/[a-z0-9]+-([^/]+)\/(bin|share\/applications)\/(\S+)$/)
            if (!m || m[1].startsWith("(")) continue
            const attr = m[1].replace(/\.out$/, "")
            const desktop = m[3] !== "bin"
            // В бинарниках — только те, где запрос в самом имени (регэксп
            // без регистра ловит и лишнее), и без служебных wrapped
            if (!desktop && (m[4].startsWith(".") || !m[4].toLowerCase().includes(lq))) continue
            const k = attr + "/" + m[4]
            if (seen[k]) continue
            seen[k] = true
            const x = { attr, version: m[2].match(/-(\d[^-]*)$/)?.[1] ?? "" }
            if (desktop) x.desktop = m[4]
            else x.bin = m[4]
            list.push(x)
        }
        // Приложения выше; дальше точное имя, начало, короче
        const name = x => (x.bin ?? x.desktop.replace(/\.desktop$/, "")).toLowerCase()
        const rank = x => (x.desktop ? 0 : 10000)
            + (name(x) === lq || name(x).endsWith("." + lq) ? 0 : name(x).startsWith(lq) ? 1000 : 2000)
            + (pkg(x) === lq ? 0 : 100) + name(x).length
        list.sort((a, b) => rank(a) - rank(b))
        return list.slice(0, 80)
    }

    // gimp.desktop → gimp; у обратных доменных (org.telegram.desktop) —
    // имя пакета, сам id — в подписи
    function appName(x) {
        const id = x.desktop.replace(/\.desktop$/, "")
        return id.includes(".") ? pkg(x) : id
    }

    // Атрибут без выхода: qrencode.bin → qrencode, kdePackages.kate — как есть
    function pkg(x) {
        return x.attr.replace(/\.(out|bin)$/, "")
    }

    function title(x) {
        return x.desktop ? appName(x) : x.bin
    }

    function start(x, args, terminal) {
        LauncherState.remember("nix", Object.assign({}, x, { args: args.join(" ") }),
            y => y.attr + "/" + (y.bin ?? y.desktop) + " " + y.args)
        NixRun.run({ attr: x.attr, bin: x.bin, desktop: x.desktop, title: title(x), args, terminal })
    }

    function item(x, recent) {
        const args = recent ? (x.args ? x.args.split(" ") : []) : restArgs
        const shown = title(x) + (args.length ? " " + args.join(" ") : "")
        return {
            glyph: x.desktop ? "󰀻" : "󱄅",
            glyphColor: recent ? Theme.overlay2 : x.desktop ? Theme.mauve : Theme.blue,
            title: shown,
            sub: "nixpkgs#" + pkg(x) + (x.version ? "   ·   " + x.version : "")
                + (x.desktop ? "   ·   " + x.desktop : "") + (recent ? "   ·   недавнее" : ""),
            badge: (x.desktop ? "⏎ запустить" : "⏎ запустить   ⇧⏎ в терминале") + (recent ? "   ⇧Del забыть" : ""),
            ghostSource: recent ? undefined : (x.bin ?? undefined),
            run: shift => start(x, args, shift && !x.desktop),
            tab: () => launcher.setQuery("," + (x.bin ?? pkg(x)) + " "),
            handoff: {
                app: "search.nixos.org",
                run: () => Tools.open("https://search.nixos.org/packages?channel=unstable&show="
                    + pkg(x) + "&query=" + encodeURIComponent(pkg(x)))
            },
            del: recent ? () => LauncherState.forget("nix",
                y => y.attr === x.attr && y.bin === x.bin && y.desktop === x.desktop && y.args === x.args) : undefined
        }
    }

    function jobItems() {
        return NixRun.jobs.map(j => {
            return {
                glyph: "󰇚",
                glyphColor: Theme.green,
                title: j.spec.title + ((j.spec.args ?? []).length ? " " + j.spec.args.join(" ") : ""),
                sub: NixRun.status(j),
                progress: j.expected > 0 ? j.done / j.expected : -1,
                progressWavy: true,
                badge: "запустится само   ⇧Del отменить",
                run: () => {},
                del: () => NixRun.cancel(j)
            }
        })
    }

    function items() {
        const q = word
        const out = jobItems()
        if (q === "") {
            const r = LauncherState.recentOf("nix")
            if (r.length) return [...out, ...r.map(x => item(x, true))]
            if (out.length) return out
            return [{ glyph: "󱄅", glyphColor: Theme.overlay1, title: "Какую программу запустить?",
                      sub: ",gimp   ·   ,cowsay привет   ·   поиск по базе nix-index", run: () => {} }]
        }
        if (last?.q === q) {
            if (last.error) out.push({ glyph: "󱄅", glyphColor: Theme.red, title: last.error, run: () => {} })
            out.push(...last.list.map(x => item(x, false)))
        } else if (q.length >= 2)
            out.push({ glyph: "󰔟", glyphColor: Theme.overlay1, title: "Ищу в nix-index…", sub: q, progress: -1, run: () => {} })
        // Имя пакета как есть — его основная программа (meta.mainProgram)
        if (/^[A-Za-z0-9_.+-]+$/.test(q))
            out.push({
                glyph: "󱄅",
                glyphColor: Theme.overlay1,
                title: "nix run nixpkgs#" + q + (rest ? " " + rest : ""),
                sub: "Пакет с таким именем, его основная программа",
                badge: "⏎ запустить   ⇧⏎ в терминале",
                run: shift => NixRun.run({ attr: q, mainProgram: true, title: q, args: restArgs, terminal: shift })
            })
        return out
    }
}
