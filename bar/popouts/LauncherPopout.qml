pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import "../../config"
import "../../services"
import "../../components"
import "../../components/Colors.js" as Colors
import "launcher"
import "launcher/Match.js" as Match

// Лончер — выпадающее меню из бара. Кроме приложений умеет режимы по префиксу:
//   =  калькулятор (qalc)      $  переменные калькулятора
//   >  команда zsh             :  окна
//   !  действия                #  буфер обмена (и цвета #rrggbb)
//   ~  файлы, ~/ и / — пути    ;  эмодзи и nerd-иконки
//   ,  запуск через nix        ?  список режимов
//   kill …  процессы           port …  занятые порты
//   docker …  контейнеры       kube …  поды
//   tr …  переводчик           gif …  гифки        qr …  QR-код
// Автодополнение везде одинаковое: серый хвост принимается →,
// Tab подставляет выбранный пункт списка (или открывает его действия).
// Ctrl+⏎ — передать наработку в полноценное приложение: выражение — в
// Qalculate, контейнер — в lazydocker, под — в k9s, перевод — в браузер…
// Здесь — строка ввода, история и список; сами режимы — в launcher/.
Item {
    id: root

    implicitWidth: 620
    implicitHeight: 480

    property string query: ""
    property int selIdx: 0

    // Подрежим поверх обычного: null | {kind: "menu", glyph, title, items: () => [...]}
    // | {kind: "picker", back} | {kind: "history", back}
    property var sub: null
    readonly property bool inMenu: sub?.kind === "menu"

    // Меню действий пункта (Tab): у приложения, контейнера, пода
    function openMenu(glyph, title, items) {
        sub = { kind: "menu", glyph, title, items }
        selIdx = 0
    }

    // Опасное — со второго Enter: первый только запоминает ключ, пункт
    // перекрашивается. Сбрасывается вводом и сменой выделения
    property string confirmKey: ""
    function confirmed(key) {
        if (confirmKey === key) {
            confirmKey = ""
            return true
        }
        confirmKey = key
        return false
    }
    onSelIdxChanged: confirmKey = ""

    // ===== Режим по префиксу =====

    readonly property var modes: ({
        apps:    { icon: "󰍉", color: Theme.mauve,    hint: "Поиск приложений…   (? — все режимы)" },
        calc:    { icon: "󰃬", color: Theme.peach,    hint: "Выражение: 2^10, 10 km to mi, x = 42, plot(sin(x))…" },
        vars:    { icon: "󰫧", color: Theme.peach,    hint: "Переменные калькулятора" },
        shell:   { icon: "󰆍", color: Theme.green,    hint: "Команда zsh…" },
        windows: { icon: "", color: Theme.blue,     hint: "Открытые окна…" },
        actions: { icon: "󰐥", color: Theme.red,      hint: "Действия: питание, скриншоты, пипетка…" },
        clip:    { icon: "󰅍", color: Theme.yellow,   hint: "Буфер обмена… (#rrggbb — цвет)" },
        files:   { icon: "󰈞", color: Theme.sapphire, hint: "Поиск файлов в ~…" },
        path:    { icon: "", color: Theme.sapphire, hint: "Путь…" },
        glyphs:  { icon: "󰞅", color: Theme.pink,     hint: "Эмодзи и иконки: кот, heart, nf-md-cat…" },
        kill:    { icon: "󰆴", color: Theme.red,      hint: "Процесс…" },
        picker:  { icon: "󰏘", color: Theme.pink,     hint: "Цвет: #hex, rgb(), hsl()…" },
        history: { icon: "󰋚", color: Theme.lavender, hint: "Поиск по истории запросов…" },
        ports:   { icon: "󰈀", color: Theme.sapphire, hint: "Порт или процесс…" },
        docker:  { icon: "󰡨", color: Theme.blue,     hint: "Контейнер…" },
        kube:    { icon: "󱃾", color: Theme.blue,     hint: "Под или неймспейс…   (@ — контексты)" },
        nix:     { icon: "󱄅", color: Theme.blue,     hint: "Программа из nixpkgs и аргументы…" },
        translate: { icon: "󰗊", color: Theme.teal,   hint: "Текст для перевода…   (de: — на немецкий)" },
        gif:     { icon: "󰵸", color: Theme.pink,     hint: "Поиск гифок…" },
        qr:      { icon: "󰐲", color: Theme.text,     hint: "Текст для QR…   (пусто — из буфера)" },
        sys:     { icon: "󰒓", color: Theme.mauve,    hint: "Система: vol, mic, br, bt, wifi, mp…" },
        modes:   { icon: "󰘳", color: Theme.lavender, hint: "Режим…" }
    })

    // Режимы со словом-префиксом: «kill …», «docker …» (слово и пробел)
    readonly property var wordModes: ({
        kill: "kill", port: "ports", ports: "ports", docker: "docker", dk: "docker",
        kube: "kube", k8s: "kube", kubectl: "kube", tr: "translate", gif: "gif", qr: "qr"
    })

    // Система: «q vol 30», «q br +10», «q bt» — первое слово после q
    // задаёт тему SysMode; без темы — список команд
    readonly property var sysWords: ({
        vol: "vol", v: "vol", mic: "mic", br: "br", bt: "bt",
        wifi: "wifi", wf: "wifi", mp: "media", media: "media",
        idle: "idle", caf: "idle", coffee: "idle", sleep: "idle"
    })

    function parseQuery(q) {
        if (/^q\s/.test(q)) {
            const rest = q.slice(1).replace(/^\s+/, "")
            const c = rest.match(/^(\S+)(\s+|$)/)
            const topic = c ? sysWords[c[1].toLowerCase()] ?? "" : ""
            return topic
                ? { mode: "sys", topic, arg: rest.slice(c[0].length), cut: q.length - rest.length + c[0].length }
                : { mode: "sys", topic: "", arg: rest, cut: q.length - rest.length }
        }
        const w = q.match(/^([a-z0-9]+)\s+/)
        if (w && wordModes[w[1]]) {
            const m = wordModes[w[1]]
            const rest = q.slice(w[0].length)
            return { mode: m, arg: m === "qr" ? rest : rest.trim(), cut: w[0].length }
        }
        switch (q.charAt(0)) {
        case "=": return { mode: "calc", arg: q.slice(1), cut: 1 }
        case "$": return { mode: "vars", arg: q.slice(1).trim(), cut: 1 }
        case ">": return { mode: "shell", arg: q.slice(1).replace(/^\s+/, ""), cut: q.length - q.slice(1).replace(/^\s+/, "").length }
        case ":": return { mode: "windows", arg: q.slice(1).trim(), cut: 1 }
        case "!": return { mode: "actions", arg: q.slice(1).trim(), cut: 1 }
        case "#": return { mode: "clip", arg: q.slice(1), cut: 1 }
        case ";": return { mode: "glyphs", arg: q.slice(1).trim(), cut: 1 }
        case ",": return { mode: "nix", arg: q.slice(1), cut: 1 }
        case "?": return { mode: "modes", arg: q.slice(1).trim(), cut: 1 }
        case "/": return { mode: "path", arg: q, cut: 0 }
        case "~":
            if (q.startsWith("~/")) return { mode: "path", arg: q, cut: 0 }
            return { mode: "files", arg: q.slice(1).trim(), cut: 1 }
        }
        return { mode: "apps", arg: q, cut: 0 }
    }

    readonly property var parsed: {
        const q = query
        if (sub && sub.kind === "picker") return { mode: "picker", arg: q, cut: 0 }
        if (sub && sub.kind === "history") return { mode: "history", arg: q, cut: 0 }
        return parseQuery(q)
    }
    readonly property string mode: parsed.mode
    readonly property string arg: parsed.arg
    readonly property string topic: parsed.topic ?? ""
    readonly property var sysTopics: sysMode.topics
    readonly property var modeInfo: mode === "sys" ? sysMode.info : modes[mode]

    // ===== Режимы =====

    AppsMode { id: appsMode; launcher: root }
    CalcMode { id: calcMode; launcher: root }
    ShellMode { id: shellMode; launcher: root }
    WindowsMode { id: windowsMode; launcher: root }
    ActionsMode { id: actionsMode; launcher: root }
    ClipMode { id: clipMode; launcher: root }
    FilesMode { id: filesMode; launcher: root }
    KillMode { id: killMode; launcher: root }
    GlyphsMode { id: glyphsMode; launcher: root }
    PortsMode { id: portsMode; launcher: root }
    DockerMode { id: dockerMode; launcher: root }
    KubeMode { id: kubeMode; launcher: root }
    NixMode { id: nixMode; launcher: root }
    TranslateMode { id: translateMode; launcher: root }
    GifMode { id: gifMode; launcher: root }
    QrMode { id: qrMode; launcher: root }
    SysMode { id: sysMode; launcher: root }
    ModesMode { id: modesMode; launcher: root }

    // ===== Цвета =====

    function colorItem(text) {
        const c = Colors.parse(text)
        if (!c) return []
        return [{
            big: true,
            swatch: Qt.rgba(c.r, c.g, c.b, c.a),
            title: Colors.hex(c),
            sub: Colors.rgb(c) + "   " + Colors.hsl(c),
            badge: "⏎ колесо   ⇧⏎ копировать",
            run: shift => {
                if (shift) {
                    Tools.copy(Colors.hex(c))
                    Ui.closePopouts()
                } else {
                    openPicker(Colors.hex(c))
                }
            }
        }]
    }

    function openPicker(text) {
        sub = { kind: "picker", back: query }
        const c = Colors.parse(text) ?? { r: 0.8, g: 0.65, b: 0.97, a: 1 }
        picker.setColor(c)
        setQuery(Colors.hex(c))
    }

    // ===== Итоговый список =====

    readonly property var results: {
        if (inMenu)
            return sub.items()
        switch (mode) {
        case "picker": return []
        case "history": return historyItems()
        case "calc": return [...calcMode.items(), ...calcMode.nameItems()]
        case "vars": return calcMode.varItems()
        case "shell": return shellMode.items()
        case "windows": return windowsMode.items()
        case "actions": return actionsMode.items(arg)
        case "clip": return clipMode.items()
        case "files": return filesMode.filesItems()
        case "path": return filesMode.pathItems()
        case "kill": return killMode.items()
        case "glyphs": return glyphsMode.items()
        case "ports": return portsMode.items()
        case "docker": return dockerMode.items()
        case "kube": return kubeMode.items()
        case "nix": return nixMode.items()
        case "translate": return translateMode.items()
        case "gif": return gifMode.items()
        case "qr": return qrMode.items()
        case "sys": return sysMode.items()
        case "modes": return modesMode.items()
        }
        // Обычный поиск: калькулятор, цвет, приложения, потом действия
        const out = [...calcMode.items(), ...colorItem(/^(rgb|hsl|hsv)a?\(/i.test(arg.trim()) ? arg : ""), ...appsMode.results(arg)]
        if (arg.trim().length >= 2)
            out.push(...actionsMode.items(arg.trim()).slice(0, 4))
        return out
    }

    readonly property var selected: results[selIdx] ?? null

    // ===== Передать в приложение (Ctrl+⏎) =====
    // {app, run}: у выделенного пункта — свой, иначе — у режима целиком
    readonly property var handoff: {
        if (sub && !inMenu) return null
        if (selected?.handoff) return selected.handoff
        switch (mode) {
        case "calc": return calcMode.handoff()
        case "docker": return dockerMode.handoff()
        case "kube": return kubeMode.handoff()
        case "translate": return translateMode.handoff()
        case "shell":
            return arg.trim() === "" ? null
                : { app: Settings.terminal[0], run: () => Zsh.runInTerminal(arg) }
        }
        return null
    }

    function runHandoff() {
        const h = handoff
        if (!h) return
        remember()
        h.run()
        // keepOpen — пункт сам закроет лончер, когда доделает (QR сохраняется)
        if (!h.keepOpen) Ui.closePopouts()
    }

    // ===== Призрачная подсказка (хвост, который допишется по →) =====

    readonly property string ghost: {
        const q = query
        if (q === "" || sub) return ""
        if (mode === "shell") return shellMode.ghost()
        if (mode === "calc") return calcMode.ghost()
        if (mode === "path") return filesMode.pathGhost()
        const top = results.find(it => it.ghostSource !== undefined)
        const a = arg.trim()
        if (!top || a === "" || arg !== a && mode !== "apps") return ""
        if (top.ghostSource.toLowerCase().startsWith(a.toLowerCase()) && arg.endsWith(a))
            return top.ghostSource.slice(a.length)
        return ""
    }

    function acceptGhost() {
        if (ghost === "") return false
        setQuery(query + ghost)
        return true
    }

    // ===== Ввод =====

    property bool _settingQuery: false

    function setQuery(t) {
        _settingQuery = true
        searchInput.text = t
        searchInput.cursorPosition = t.length
        _settingQuery = false
    }

    onQueryChanged: {
        actionsMode.confirmId = ""
        confirmKey = ""
        asyncTimer.restart()
        netTimer.restart()
        if (mode === "calc" || mode === "apps") calcMode.schedule()
    }

    onModeChanged: {
        if (mode === "clip") clipMode.refresh()
        if (mode === "shell") { Zsh.start(); Zsh.refreshHistory() }
        if (mode === "qr") qrMode.refreshClip()
    }

    onResultsChanged: if (selIdx >= results.length) selIdx = 0

    // Ввод текста сбрасывает выделение на первый пункт
    function resetSel() {
        selIdx = 0
        list.positionViewAtBeginning()
    }

    Timer {
        id: asyncTimer
        interval: 90
        onTriggered: {
            if (root.mode === "shell") shellMode.request()
            else if (root.mode === "files") filesMode.request()
            else if (root.mode === "qr") qrMode.request()
        }
    }

    // Сеть и nix-locate — подольше: не на каждую букву
    Timer {
        id: netTimer
        interval: 350
        onTriggered: {
            if (root.mode === "gif") gifMode.request()
            else if (root.mode === "translate") translateMode.request()
            else if (root.mode === "nix") nixMode.request()
        }
    }


    Component.onCompleted: {
        const preset = Tools.launcherPreset
        Tools.launcherPreset = ""
        if (preset.startsWith("color:"))
            openPicker(preset.slice(6))
        else if (preset !== "")
            setQuery(preset)
        searchInput.forceActiveFocus()
    }

    // ===== История запросов =====
    // Ctrl+↑/↓ (или ↑ в пустой строке) листают историю; если что-то уже введено —
    // только запросы, начинающиеся с введённого (как up-line-or-search в zsh).
    // Ctrl+R — список истории с поиском.

    property int histPos: -1          // -1 — не листаем
    property string histDraft: ""     // что было введено до начала листания
    property bool _histSetting: false
    property bool histArrows: false   // листание начато простой ↑ — тогда и ↓ листает

    // Запрос, который сейчас выполнится — в историю
    // noHistory у пункта — запрос с секретом (gif key …), не запоминать
    function remember() {
        if (sub && (sub.kind === "history" || sub.kind === "picker")) return
        if (selected?.noHistory) return
        Tools.addQuery(query)
    }

    function histMatches() {
        return Tools.queries.filter(q => q.startsWith(histDraft) && q !== histDraft)
    }

    function histStep(d) {
        if (histPos === -1) {
            if (d > 0) return false
            histDraft = query
        }
        const list = histMatches()
        const next = histPos - d
        if (next >= list.length) return true
        histPos = Math.max(-1, next)
        _histSetting = true
        setQuery(histPos === -1 ? histDraft : list[histPos])
        _histSetting = false
        return true
    }

    function openHistory() {
        sub = { kind: "history", back: query }
        selIdx = 0
        histPos = -1
    }

    function modeIcon(q) {
        const m = parseQuery(q).mode
        if (m === "sys") return sysTopics[parseQuery(q).topic] ?? modes.sys
        if (m !== "apps") return modes[m]
        return Calc.looksLikeMath(q) ? modes.calc : modes.apps
    }

    function historyItems() {
        return Match.filterBy(Tools.queries, arg, q => [q]).slice(0, 200).map(q => {
            const m = modeIcon(q)
            return {
                glyph: m.icon,
                glyphColor: m.color,
                title: q,
                badge: "⏎ в строку   ⇧⏎ выполнить   ⇧Del удалить",
                run: shift => {
                    sub = null
                    setQuery(q)
                    if (shift) Qt.callLater(() => root.runSelected(false))
                },
                del: () => Tools.removeQuery(q)
            }
        })
    }

    function runSelected(shift) {
        if (sub && sub.kind === "picker") {
            picker.activate()
            if (!shift) Ui.closePopouts()
            return
        }
        if (selected) {
            remember()
            selected.run(shift)
        }
    }

    function tabSelected() {
        const it = selected
        if (mode === "shell" && selIdx === 0 && !sub) return shellMode.tab()
        if (!it) return acceptGhost()
        if (it.tab) { it.tab(); return true }
        if (typeof it.complete === "string") { setQuery(it.complete); return true }
        return acceptGhost()
    }

    function back() {
        if (!sub) return false
        if (sub.kind === "picker" || sub.kind === "history") {
            const q = sub.back
            sub = null
            setQuery(q)
        } else {
            sub = null
        }
        selIdx = 0
        return true
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        anchors.bottomMargin: 10
        spacing: 10

        // Поиск
        Item {
            width: parent.width
            height: 36

            Text {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                horizontalAlignment: Text.AlignHCenter
                text: root.inMenu ? root.sub.glyph : root.modeInfo.icon
                font.family: Theme.font
                font.pixelSize: 16
                color: root.modeInfo.color
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            TextInput {
                id: searchInput
                anchors.left: searchIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font
                font.pixelSize: 16
                color: Theme.text
                selectionColor: Theme.surface1
                clip: true

                onTextChanged: {
                    root.query = text
                    if (!root._histSetting)
                        root.histPos = -1
                    if (root._settingQuery) {
                        root.resetSel()
                        return
                    }
                    if (root.inMenu)
                        root.sub = null
                    if (root.sub?.kind === "picker") {
                        const c = Colors.parse(text)
                        if (c) picker.setColor(c)
                        return
                    }
                    root.resetSel()
                }

                Keys.onPressed: event => {
                    const shift = event.modifiers & Qt.ShiftModifier
                    const ctrl = event.modifiers & Qt.ControlModifier
                    const inPicker = root.sub?.kind === "picker"
                    const step = d => {
                        if (inPicker) picker.move(d)
                        else root.selIdx = Math.max(0, Math.min(root.selIdx + d, root.results.length - 1))
                    }
                    switch (event.key) {
                    case Qt.Key_Escape:
                        if (!root.back()) Ui.closePopouts()
                        break
                    case Qt.Key_Down:
                        if (inPicker && ctrl) picker.nudge(0, 0, -0.03)
                        else if (!root.sub && (ctrl || root.histPos >= 0 && root.histArrows)) root.histStep(1)
                        else step(1)
                        break
                    case Qt.Key_Up:
                        if (inPicker && ctrl) picker.nudge(0, 0, 0.03)
                        else if (!root.sub && ctrl) {
                            if (root.histPos === -1) root.histArrows = false
                            root.histStep(-1)
                        }
                        // Простая ↑ уходит в историю из пустой строки (как в терминале),
                        // дальше ↑↓ листают её, пока не начнёшь печатать
                        else if (!root.sub && root.selIdx === 0
                                 && (root.query === "" && root.histPos === -1 || root.histPos >= 0 && root.histArrows)) {
                            if (root.histPos === -1) root.histArrows = true
                            root.histStep(-1)
                        } else step(-1)
                        break
                    case Qt.Key_P:
                    case Qt.Key_N:
                        if (!ctrl || root.sub) { event.accepted = false; return }
                        if (root.histPos === -1) root.histArrows = false
                        root.histStep(event.key === Qt.Key_P ? -1 : 1)
                        break
                    case Qt.Key_R:
                        if (!ctrl) { event.accepted = false; return }
                        if (root.sub?.kind === "history") root.back()
                        else if (!root.sub) root.openHistory()
                        break
                    case Qt.Key_PageDown:
                        step(8)
                        break
                    case Qt.Key_PageUp:
                        step(-8)
                        break
                    case Qt.Key_Left:
                        if (inPicker && ctrl) { picker.nudge(-2 / 360, 0, 0); break }
                        if (ctrl && root.selected?.nudge) { root.selected.nudge(-1); break }
                        if (root.inMenu && searchInput.cursorPosition === 0) { root.back(); break }
                        event.accepted = false
                        return
                    case Qt.Key_Right:
                        if (inPicker && ctrl) { picker.nudge(2 / 360, 0, 0); break }
                        if (ctrl && root.selected?.nudge) { root.selected.nudge(1); break }
                        if (searchInput.cursorPosition === searchInput.text.length && root.acceptGhost()) break
                        event.accepted = false
                        return
                    case Qt.Key_End:
                        if (searchInput.cursorPosition === searchInput.text.length && root.acceptGhost()) break
                        event.accepted = false
                        return
                    case Qt.Key_Tab:
                        root.tabSelected()
                        break
                    case Qt.Key_Backtab:
                        root.back()
                        break
                    case Qt.Key_Delete:
                        if (shift && root.selected?.del) {
                            root.selected.del()
                            break
                        }
                        event.accepted = false
                        return
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (ctrl) root.runHandoff()
                        else root.runSelected(shift)
                        break
                    case Qt.Key_O:
                        if (!ctrl) { event.accepted = false; return }
                        root.runHandoff()
                        break
                    default:
                        event.accepted = false
                        return
                    }
                    event.accepted = true
                }

                // Призрачный хвост автодополнения
                Text {
                    visible: root.ghost !== "" && searchInput.cursorPosition === searchInput.text.length
                        && searchInput.contentWidth < searchInput.width - 40
                    x: searchInput.contentWidth
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.ghost
                    font.family: Theme.font
                    font.pixelSize: 16
                    color: Theme.overlay0
                }

                Text {
                    anchors.fill: parent
                    visible: searchInput.text === ""
                    text: root.inMenu ? root.sub.title + " — действия" : root.modeInfo.hint
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.italic: true
                    color: Theme.overlay0
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // Градиентный разделитель
        Rectangle {
            width: parent.width
            height: 1
            gradient: OkGradient {
                orientation: Gradient.Horizontal
                from: Theme.alpha(Theme.gradStart, 0.6)
                to: Theme.alpha(Theme.gradEnd, 0.6)
            }
        }

        Item {
            width: parent.width
            height: parent.height - 36 - 1 - 20 - 20

            ColorPicker {
                id: picker
                anchors.fill: parent
                anchors.topMargin: 6
                visible: root.sub?.kind === "picker"
                onEdited: {
                    if (root.sub?.kind === "picker")
                        root.setQuery(Colors.hex(picker.rgba))
                }
                onCopyRequested: text => Tools.copy(text)
                onPickRequested: {
                    Ui.closePopouts()
                    Tools.pickColor()
                }
            }

            Overscroll {
                flick: list
                z: 1
                visible: list.visible
            }

            ListView {
                id: list
                anchors.fill: parent
                visible: !picker.visible
                clip: true
                model: root.results
                currentIndex: root.selIdx
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 200

                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: ResultRow {
                    width: list.width
                    selected: index === root.selIdx
                    onActivated: shift => {
                        root.selIdx = index
                        root.remember()
                        modelData.run(shift)
                        searchInput.forceActiveFocus()
                    }
                }
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: hint + (root.handoff && !root.sub?.kind?.match(/picker|history/) && root.histPos < 0
                ? "   ·   Ctrl+⏎ → " + root.handoff.app : "")
            readonly property string hint: {
                if (root.sub?.kind === "picker")
                    return "↑↓ формат   ·   ⏎ копировать   ·   Ctrl+←→ оттенок   ·   Ctrl+↑↓ яркость   ·   Esc назад"
                if (root.inMenu)
                    return "↑↓ навигация   ·   ⏎ выполнить   ·   Esc/⇧Tab назад"
                if (root.sub?.kind === "history")
                    return "⏎ в строку   ·   ⇧⏎ выполнить   ·   ⇧Del удалить   ·   Esc назад"
                if (root.histPos >= 0)
                    return "История " + (root.histPos + 1) + "/" + root.histMatches().length
                        + "   ·   " + (root.histArrows ? "↑↓" : "Ctrl+↑↓") + " листать   ·   печатай — выйти"
                const n = root.results.length
                const hints = {
                    apps: n + " результатов   ·   ⏎ запуск   ·   Tab действия   ·   ↑ / Ctrl+R история",
                    calc: calcMode.plotData ? "⏎ открыть в gnuplot   ·   plot(f, от, до)   ·   наведи — значение"
                        : "⏎ копировать   ·   ⇧⏎ в ans   ·   x = 2+2 — переменная   ·   plot(f) — график",
                    shell: "⏎ фон   ·   ⇧⏎ терминал   ·   Tab дополнить   ·   → из истории",
                    path: "⏎ открыть / войти   ·   Tab войти   ·   → дописать",
                    files: "⏎ открыть   ·   ⇧⏎ папку   ·   Tab в путь",
                    ports: n + " портов   ·   ⏎ открыть в браузере   ·   ⇧⏎ копировать   ·   ⇧Del TERM",
                    docker: "⏎ шелл / запустить   ·   Tab действия   ·   обновляется раз в 2 с",
                    kube: (kubeMode.info.context ? "контекст " + kubeMode.info.context + "   ·   " : "")
                        + "⏎ логи   ·   Tab действия   ·   kube @ — контексты",
                    nix: "⏎ запустить   ·   ⇧⏎ в терминале   ·   Tab в строку   ·   nix-index",
                    translate: Settings.translateLangs.join(" ⇄ ") + "   ·   ⏎ копировать   ·   ⇧⏎ перевести обратно",
                    gif: "⏎ ссылка   ·   ⇧⏎ гифка в буфер   ·   " + (Settings.gifProvider === "giphy" ? "GIPHY" : "Klipy"),
                    qr: "⏎ копировать картинку   ·   ⇧⏎ открыть",
                    sys: root.topic === "" ? "⏎ / Tab — выбрать команду   ·   → дописать"
                        : "⏎ сделать и закрыть   ·   ⇧⏎ сделать и остаться   ·   Ctrl+←→ ±5%",
                    modes: "⏎ перейти в режим"
                }
                return hints[root.mode] ?? (n + " результатов   ·   ↑↓ навигация   ·   ⏎ выбрать   ·   Esc закрыть")
            }
            font.family: Theme.font
            font.pixelSize: 10
            color: Theme.overlay0
        }
    }
}