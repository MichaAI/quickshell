import QtQuick
import Quickshell
import Quickshell.Io

// driftwm: снапшоты `driftwm msg --json subscribe` и команды `driftwm msg`.
// Снаружи — только через Compositor. Воркспейсов нет (один холст), трансляции
// идут через xdg-desktop-portal — driftwm о них не рассказывает
Scope {

    id: root

    // Слушать сокет, только когда шелл и правда под driftwm
    property bool active: false

    readonly property bool hasWorkspaces: false
    readonly property bool hasCasts: false
    readonly property bool canPowerOffMonitors: false
    readonly property var pickColorCommand: []

    // ====== Из снапшота ======
    property var windows: []             // [{id, title, app_id, pid, is_focused, is_floating}] — как у niri
    property string currentLang: ""
    property string focusedOutput: ""

    readonly property var workspaces: []
    readonly property var casts: []
    // Обзор driftwm — просто зум камеры, отдельного состояния у него нет
    readonly property bool overviewOpen: false

    readonly property var focusedWindow: windows.find(w => w.is_focused) ?? null
    readonly property int focusedWindowId: focusedWindow?.id ?? -1

    // Снапшот приходит целиком на каждое изменение, а пока что-то едет
    // (пан, перетаскивание) — каждый кадр. Окна пересобираем, только если
    // поменялось то, что видят виджеты
    property string _windowsKey: ""

    function _apply(s) {
        root.currentLang = s.layout ?? ""
        root.focusedOutput = (s.outputs ?? []).find(o => o.active)?.name ?? ""

        // Виджеты (часы, трей на холсте) фокус не берут — это не окна
        const list = (s.windows ?? []).filter(w => !w.is_widget).map(w => ({
            id: w.id, title: w.title, app_id: w.app_id, pid: w.pid,
            is_focused: w.is_focused, is_floating: false
        }))
        // Полноэкранные и прибитые к экрану живут вне холста и приходят
        // отдельно, без фокуса. Если на холсте фокуса нет, а на активном
        // мониторе что-то на весь экран — фокус почти наверняка у него
        const canvasFocused = list.some(w => w.is_focused)
        for (const f of s.fullscreen ?? [])
            list.push({ id: f.id, title: f.title, app_id: f.app_id,
                        is_focused: !canvasFocused && f.output === root.focusedOutput,
                        is_floating: false })
        for (const p of s.pinned ?? [])
            list.push({ id: p.id, title: p.title, app_id: p.app_id,
                        is_focused: false, is_floating: true })

        const key = JSON.stringify(list)
        if (key !== root._windowsKey) {
            root._windowsKey = key
            root.windows = list
        }
    }

    Process {
        id: driftStream
        command: ["driftwm", "msg", "--json", "subscribe"]
        running: root.active

        onRunningChanged: if (!running && root.active) running = true

        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "")
                    return
                const event = JSON.parse(line)
                if (event.State)
                    root._apply(event.State)
            }
        }
    }

    // ====== Команды (один Process на все действия, через exec) ======
    Process { id: actionProc }

    function focusWindow(id) {
        actionProc.exec(["driftwm", "msg", "focus", "--id", id.toString()])
    }

    function closeWindow(id) {
        actionProc.exec(["driftwm", "msg", "close", "--id", id.toString()])
    }

    function switchLayout() {
        actionProc.exec(["driftwm", "msg", "action", "switch-layout", "next"])
    }

    function stopCast(sessionId) {}

    // Повторный zoom-to-fit возвращает камеру, где была
    function toggleOverview() {
        actionProc.exec(["driftwm", "msg", "action", "zoom-to-fit"])
    }

    function quit() {
        actionProc.exec(["driftwm", "msg", "action", "quit"])
    }

    function powerOffMonitors() {}

    // Как у niri: файл в ~/Pictures/Screenshots и картинка в буфере обмена.
    // driftwm перерисовывает холст сам, поэтому бара на снимке нет
    readonly property string shotScript: `
        dir=\${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots
        mkdir -p "$dir"
        f="$dir/Screenshot from $(date '+%Y-%m-%d %H-%M-%S').png"
        case $1 in
            area) r=$(slurp) || exit 0
                  driftwm msg screenshot region "$r" --from-screen -o "$f" ;;
            screen) driftwm msg screenshot -o "$f" ;;
            window) driftwm msg screenshot window -o "$f" ;;
        esac && wl-copy --type image/png < "$f"`

    // area — выделить мышью, screen — монитор, window — окно в фокусе
    function screenshot(target) {
        Tools.launch(["sh", "-c", root.shotScript, "shot", target], "screenshot")
    }
}
