import QtQuick
import Quickshell
import "../../../services"
import "Match.js" as Match

// «:» — открытые окна: перейти или закрыть
Item {
    required property var launcher

    function items() {
        const ws = {}
        for (const w of Compositor.workspaces) ws[w.id] = w.idx
        return Match.filterBy(Compositor.windows, launcher.arg, w => [w.title ?? "", w.app_id ?? ""]).map(w => {
            const entry = DesktopEntries.heuristicLookup(w.app_id ?? "")
            return {
                iconName: entry?.icon ?? w.app_id ?? "",
                title: w.title || w.app_id || "?",
                sub: (entry?.name ?? w.app_id ?? "")
                    + (Compositor.hasWorkspaces ? "   ·   стол " + (ws[w.workspace_id] ?? "?") : "")
                    + (w.is_focused ? "   ·   в фокусе" : ""),
                badge: "⏎ перейти   ⇧Del закрыть",
                ghostSource: w.title,
                run: () => { Compositor.focusWindow(w.id); Ui.closePopouts() },
                del: () => Compositor.closeWindow(w.id)
            }
        })
    }
}
