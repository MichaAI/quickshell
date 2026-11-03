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

    // Открыт попаут бара: новые не всплывают, висящие уезжают (но остаются в центре)
    readonly property bool suppressed: Ui.openPopouts > 0
    signal hidePopupsRequested()
    onSuppressedChanged: if (suppressed) hidePopupsRequested()

    // «Очистить всё»: карточки сначала разъезжаются (лесенкой), потом удаляем
    signal clearRequested()
    readonly property bool clearing: clearTimer.running
    readonly property int clearStagger: 40
    readonly property int clearMaxSteps: 30         // дальше лесенка не растёт
    property real clearStart: 0
    readonly property int leaveDuration: 200      // уезд карточки (NotifItem)
    readonly property int collapseDuration: 160   // схлопывание места (NotifItem)

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
            if (root.suppressed)
                return
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

    // Тело для StyledText. Некоторые приложения (KDE Connect и т.п.) шлют
    // переносы экранированными — "&lt;br/&gt;", и они рисовались буквами.
    function bodyText(n) {
        return (n.body ?? "")
            .replace(/&lt;br\s*\/?&gt;/gi, "<br>")
            .replace(/<br\s*\/?>/gi, "<br>")
            .replace(/\r?\n/g, "<br>")
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
        clearStart = Date.now()
        // Ровно когда закончит анимацию последняя карточка волны
        clearTimer.deadline = clearStart + clearDelay(count - 1)
            + leaveDuration + collapseDuration
        clearTimer.interval = clearTimer.deadline - clearStart
        clearTimer.start()
        clearRequested()
    }

    // Сколько карточке с этим индексом ждать до своего места в волне.
    // Часы общие для всех: и для созданных сразу, и для ленивых делегатов,
    // которые появляются позже, — иначе волна рвётся.
    function clearDelay(index) {
        const at = clearStart + Math.min(index, clearMaxSteps) * clearStagger
        return Math.max(0, at - Date.now())
    }

    // Поздняя карточка уходит с задержкой delay — дождаться конца её анимации
    function holdClear(delay) {
        const end = Date.now() + delay + leaveDuration + collapseDuration
        if (!clearTimer.running || end <= clearTimer.deadline)
            return
        clearTimer.deadline = end
        clearTimer.interval = end - Date.now()
        clearTimer.restart()
    }

    Timer {
        id: clearTimer
        property real deadline: 0
        onTriggered: {
            for (const n of [...server.trackedNotifications.values]) // qmllint disable missing-property
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
