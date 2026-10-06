pragma Singleton
import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// Сервер уведомлений: история для центра + очередь всплывашек.
Singleton {
    id: root

    property bool dnd: false
    property bool unread: false

    // Новые сверху
    readonly property var list: [...server.trackedNotifications.values].reverse()
    readonly property int count: list.length

    // Всплывашки (Notification), новые сверху
    property var popups: []
    // id -> время получения (у самого Notification его нет)
    property var times: ({})

    readonly property int popupTimeout: 6000

    // «Очистить всё»: карточки сначала разъезжаются (лесенкой), потом удаляем
    signal clearRequested()
    readonly property int clearStagger: 40

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true
            root.times[n.id] = new Date()
            root.timesChanged()

            n.closed.connect(() => root.dropPopup(n))

            if (n.lastGeneration)
                return
            root.unread = true
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.popups = [n, ...root.popups].slice(0, 5)
        }
    }

    function dropPopup(n) {
        if (popups.includes(n))
            popups = popups.filter(p => p !== n)
    }

    // Всплывашка истекла: transient-уведомлениям в центре не место
    function popupExpired(n) {
        dropPopup(n)
        if (n.transient)
            n.expire()
    }

    function timeOf(n) {
        return times[n.id] ?? null
    }

    function ago(n) {
        const t = timeOf(n)
        if (!t) return ""
        const s = Math.floor((Time.now - t) / 1000)
        if (s < 60) return "сейчас"
        if (s < 3600) return Math.floor(s / 60) + " мин"
        if (s < 86400) return Math.floor(s / 3600) + " ч"
        return Qt.formatDateTime(t, "d MMM")
    }

    // Клик по карточке — действие по умолчанию, если есть
    function activate(n) {
        const def = n.actions.find(a => a.identifier === "default")
        if (def)
            def.invoke()
        else if (!n.resident)
            n.dismiss()
    }

    function clearAll() {
        if (count === 0 || clearTimer.running)
            return
        unread = false
        clearRequested()
        clearTimer.interval = 400 + Math.min(count, 10) * clearStagger
        clearTimer.start()
    }

    Timer {
        id: clearTimer
        onTriggered: {
            for (const n of [...server.trackedNotifications.values])
                n.dismiss()
            root.popups = []
        }
    }

    function toggleDnd() {
        dnd = !dnd
        if (dnd)
            popups = popups.filter(n => n.urgency === NotificationUrgency.Critical)
    }

    readonly property string icon: dnd ? "󰂛"
        : unread && count > 0 ? "󱅫"
        : "󰂚"
}
