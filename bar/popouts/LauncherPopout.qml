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
//   >  команда zsh             :  окна niri
//   !  действия                #  буфер обмена (и цвета #rrggbb)
//   ~  файлы, ~/ и / — пути    ;  эмодзи и nerd-иконки
//   kill …  процессы
// Автодополнение везде одинаковое: серый хвост принимается →,
// Tab подставляет выбранный пункт списка.
// Здесь — строка ввода, история и список; сами режимы — в launcher/.
Item {
    id: root

    implicitWidth: 620
    implicitHeight: 480

    property string query: ""
    property int selIdx: 0

    // Подрежим поверх обычного: null | {kind: "actions", app} | {kind: "picker", back}
    property var sub: null

    // ===== Режим по префиксу =====

    readonly property var modes: ({
        apps:    { icon: "󰍉", color: Theme.mauve,    hint: "Поиск приложений…   (= > : ! # ~ ; $ kill)" },
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
        history: { icon: "󰋚", color: Theme.lavender, hint: "Поиск по истории запросов…" }
    })

    readonly property var parsed: {
        const q = query
        if (sub && sub.kind === "picker") return { mode: "picker", arg: q, cut: 0 }
        if (sub && sub.kind === "history") return { mode: "history", arg: q, cut: 0 }
        if (/^kill\s/.test(q)) return { mode: "kill", arg: q.slice(5).trim(), cut: 5 }
        switch (q.charAt(0)) {
        case "=": return { mode: "calc", arg: q.slice(1), cut: 1 }
        case "$": return { mode: "vars", arg: q.slice(1).trim(), cut: 1 }
        case ">": return { mode: "shell", arg: q.slice(1).replace(/^\s+/, ""), cut: q.length - q.slice(1).replace(/^\s+/, "").length }
        case ":": return { mode: "windows", arg: q.slice(1).trim(), cut: 1 }
        case "!": return { mode: "actions", arg: q.slice(1).trim(), cut: 1 }
        case "#": return { mode: "clip", arg: q.slice(1), cut: 1 }
        case ";": return { mode: "glyphs", arg: q.slice(1).trim(), cut: 1 }
        case "/": return { mode: "path", arg: q, cut: 0 }
        case "~":
            if (q.startsWith("~/")) return { mode: "path", arg: q, cut: 0 }
            return { mode: "files", arg: q.slice(1).trim(), cut: 1 }
        }
        return { mode: "apps", arg: q, cut: 0 }
    }
    readonly property string mode: parsed.mode
    readonly property string arg: parsed.arg
    readonly property var modeInfo: modes[mode]

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
        if (sub && sub.kind === "actions")
            return appsMode.actionItems(sub.app)
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
        }
        // Обычный поиск: калькулятор, цвет, приложения, потом действия
        const out = [...calcMode.items(), ...colorItem(/^(rgb|hsl|hsv)a?\(/i.test(arg.trim()) ? arg : ""), ...appsMode.results(arg)]
        if (arg.trim().length >= 2)
            out.push(...actionsMode.items(arg.trim()).slice(0, 4))
        return out
    }

    readonly property var selected: results[selIdx] ?? null

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
        asyncTimer.restart()
        if (mode === "calc" || mode === "apps") calcMode.schedule()
    }

    onModeChanged: {
        if (mode === "clip") clipMode.refresh()
        if (mode === "shell") { Zsh.start(); Zsh.refreshHistory() }
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
    function remember() {
        if (sub && (sub.kind === "history" || sub.kind === "picker")) return
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
        if (/^kill\s/.test(q)) return modes.kill
        const m = { "=": "calc", "$": "vars", ">": "shell", ":": "windows", "!": "actions",
                    "#": "clip", ";": "glyphs", "/": "path" }[q.charAt(0)]
        if (m) return modes[m]
        if (q.charAt(0) === "~") return q.startsWith("~/") ? modes.path : modes.files
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
                text: root.sub?.kind === "actions" ? "󰁔" : root.modeInfo.icon
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
                    if (root.sub?.kind === "actions")
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
                        if (root.sub?.kind === "actions" && searchInput.cursorPosition === 0) { root.back(); break }
                        event.accepted = false
                        return
                    case Qt.Key_Right:
                        if (inPicker && ctrl) { picker.nudge(2 / 360, 0, 0); break }
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
                        root.runSelected(shift)
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
                    text: root.sub?.kind === "actions" ? root.sub.app.name + " — действия" : root.modeInfo.hint
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
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.alpha(Theme.gradStart, 0.6) }
                GradientStop { position: 1; color: Theme.alpha(Theme.gradEnd, 0.6) }
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
            elide: Text.ElideRight
            text: {
                if (root.sub?.kind === "picker")
                    return "↑↓ формат   ·   ⏎ копировать   ·   Ctrl+←→ оттенок   ·   Ctrl+↑↓ яркость   ·   Esc назад"
                if (root.sub?.kind === "actions")
                    return "↑↓ навигация   ·   ⏎ запуск   ·   Esc/⇧Tab назад"
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
                    files: "⏎ открыть   ·   ⇧⏎ папку   ·   Tab в путь"
                }
                return hints[root.mode] ?? (n + " результатов   ·   ↑↓ навигация   ·   ⏎ выбрать   ·   Esc закрыть")
            }
            font.family: Theme.font
            font.pixelSize: 10
            color: Theme.overlay0
        }
    }
}