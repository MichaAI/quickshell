pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {

    id: root

    // ====== Сырые данные с сокета ======
    property var workspaces: []          // [{id, idx, name, output, is_urgent, is_active, is_focused, active_window_id}]
    property var windows: []             // [{id, title, app_id, pid, workspace_id, is_focused, is_floating, layout, ...}]
    property int focusedWindowId: -1
    property var keyboardLayouts: ({ names: [], currentIdx: 0 })
    property bool overviewOpen: false
    property bool configLoadFailed: false
    property var casts: []

    // ====== Вычисляемые свойства под виджеты ======

    readonly property var focusedWindow:
        windows.find(w => w.id === focusedWindowId) || null

    readonly property var focusedWorkspace:
        workspaces.find(ws => ws.is_focused) || null

    readonly property string currentLang:
        keyboardLayouts.names[keyboardLayouts.currentIdx] ?? ""

    
    // {workspaceId: {colIndex: [окна, сортированы по строке]}} — под мини-карту лайаута
    readonly property var columnsByWorkspace: {
        const result = {}
        for (const w of windows) {
            const wsId = w.workspace_id
            const col = w.layout?.pos_in_scrolling_layout?.[0] ?? 0
        
            if (!result[wsId]) result[wsId] = {}
            if (!result[wsId][col]) result[wsId][col] = []
        
            result[wsId][col].push(w)
        }
        for (const wsId in result) {
            for (const col in result[wsId]) {
                result[wsId][col].sort((a, b) =>
                    (a.layout?.pos_in_scrolling_layout?.[1] ?? 0) -
                    (b.layout?.pos_in_scrolling_layout?.[1] ?? 0))
            }
        }
        return result
    }

    Process {
        id: niriStream
        command: ["niri", "msg", "--json", "event-stream"]
        running: true

        onRunningChanged: if (!running) running = true

        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "") {
                    return;
                };
                const event = JSON.parse(line);
                const type = Object.keys(event)[0];
                const data = event[type];

                 switch (type) {
                    case "WorkspacesChanged":
                        root.workspaces = data.workspaces
                        break

                    case "WindowsChanged":
                        root.windows = data.windows
                        break

                    case "WindowOpenedOrChanged": {
                        const w = data.window
                        const idx = root.windows.findIndex(x => x.id === w.id)
                        if (idx === -1) {
                            root.windows = [...root.windows, w]
                        } else {
                            const copy = [...root.windows]
                            copy[idx] = w
                            root.windows = copy
                        }
                        if (w.is_focused) root.focusedWindowId = w.id
                        break
                    }

                    case "WindowClosed": {
                        root.windows = root.windows.filter(w => w.id !== data.id)
                        if (root.focusedWindowId === data.id) root.focusedWindowId = -1
                        break
                    }


                    case "WindowLayoutsChanged": {
                        const changes = new Map(data.changes)
                        root.windows = root.windows.map(w =>
                            changes.has(w.id) ? Object.assign({}, w, { layout: changes.get(w.id) }) : w
                        )
                        break
                    }
                        
                    case "WindowFocusChanged":
                        root.focusedWindowId = data.id ?? -1
                        break

                    case "WorkspaceActiveWindowChanged":
                        root.workspaces = root.workspaces.map(ws =>
                            ws.id === data.workspace_id
                                ? Object.assign({}, ws, { active_window_id: data.active_window_id })
                                : ws
                        )
                        break

                    case "WorkspaceActivated": {
                        const target = root.workspaces.find(ws => ws.id === data.id)
                        if (!target) break
                        root.workspaces = root.workspaces.map(ws => {
                            if (ws.output !== target.output) return ws
                            return Object.assign({}, ws, {
                                is_active: ws.id === data.id,
                                is_focused: data.focused ? ws.id === data.id : ws.is_focused
                            })
                        })
                        break
                    }

                    case "KeyboardLayoutsChanged":
                        root.keyboardLayouts = {
                            names: data.keyboard_layouts.names,
                            currentIdx: data.keyboard_layouts.current_idx
                        }
                        break
                        
                    case "KeyboardLayoutSwitched":
                        root.keyboardLayouts = Object.assign({}, root.keyboardLayouts, { currentIdx: data.idx })
                        break

                    case "OverviewOpenedOrClosed":
                        root.overviewOpen = data.is_open
                        break

                    case "ConfigLoaded":
                        root.configLoadFailed = data.failed
                        break

                    case "CastsChanged":
                        root.casts = data.casts
                        break

                }
            }
        }
    }

        // ====== Команды (один Process на все действия, через exec) ======
    Process { id: actionProc }

    function focusWindow(id) {
        actionProc.exec(["niri", "msg", "action", "focus-window", "--id", id.toString()])
    }

    function focusWorkspace(idx) {
        actionProc.exec(["niri", "msg", "action", "focus-workspace", idx.toString()])
    }

    function closeWindow(id) {
        actionProc.exec(["niri", "msg", "action", "close-window", "--id", id.toString()])
    }

    function switchLayout() {
        actionProc.exec(["niri", "msg", "action", "switch-layout", "next"])
    }
}
