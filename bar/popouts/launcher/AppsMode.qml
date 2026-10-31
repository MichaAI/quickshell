import QtQuick
import Quickshell
import "../../../services"
import "Match.js" as Match

// Обычный поиск: приложения и их действия (Tab)
Item {
    id: mode

    required property var launcher

    function appScore(app, q) {
        const s = Match.score(app.name, q)
        if (s >= 60) return s
        const g = Match.score(app.genericName ?? "", q)
        if (g >= 60) return 30
        if (Match.score(Array.from(app.keywords ?? []).join(" "), q) >= 60) return 25
        if (Match.score(app.comment ?? "", q) >= 60) return 20
        return s
    }

    function launch(app, action) {
        Apps.launch(app, action)
        Ui.closePopouts()
    }

    function item(app) {
        const hasActions = Array.from(app.actions ?? []).length > 0
        return {
            iconName: app.icon,
            title: app.name,
            sub: app.genericName || app.comment || "",
            badge: hasActions ? "Tab  󰁔" : "",
            ghostSource: app.name,
            run: () => launch(app, null),
            tab: hasActions ? () => openActions(app) : null
        }
    }

    function results(q) {
        const lq = q.toLowerCase().trim()
        const freq = a => Apps.freq(a)
        if (lq === "")
            return [...Apps.list].sort((a, b) =>
                freq(b) - freq(a) || a.name.localeCompare(b.name)).map(item)
        return Apps.list
            .map(a => [appScore(a, lq), a])
            .filter(x => x[0] > 0)
            .sort((x, y) => (y[0] + freq(y[1]) * 5) - (x[0] + freq(x[1]) * 5)
                || x[1].name.localeCompare(y[1].name))
            .map(x => item(x[1]))
    }

    function openActions(app) {
        launcher.openMenu("󰁔", app.name, () => mode.actionItems(app))
    }

    // Подрежим «действия приложения»
    function actionItems(app) {
        return Array.from(app.actions ?? []).map(a => ({
            iconName: a.icon || app.icon,
            title: a.name,
            sub: app.name,
            run: () => launch(app, a)
        }))
    }
}
