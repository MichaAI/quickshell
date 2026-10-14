import QtQuick
import Quickshell
import "../../../services"
import "Match.js" as Match

// «:» — открытые окна niri: перейти или закрыть
Item {
    required property var launcher

    function items() {
        const ws = {}
        for (const w of Niri.workspaces) ws[w.id] = w.idx
        return Match.filterBy(Niri.windows, launcher.arg, w => [w.title ?? "", w.app_id ?? ""]).map(w => {
            const entry = DesktopEntries.heuristicLookup(w.app_id ?? "")
            return {
                iconName: entry?.icon ?? w.app_id ?? "",
                title: w.title || w.app_id || "?",
                sub: (entry?.name ?? w.app_id ?? "") + "   ·   стол " + (ws[w.workspace_id] ?? "?")
                    + (w.is_focused ? "   ·   в фокусе" : ""),
                badge: "⏎ перейти   ⇧Del закрыть",
                ghostSource: w.title,
                run: () => { Niri.focusWindow(w.id); Ui.closePopouts() },
                del: () => Niri.closeWindow(w.id)
            }
        })
    }
}
