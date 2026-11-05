pragma Singleton
import Quickshell
import QtQuick

// systemd-logind: блокировки (systemd-inhibit), сон, подсказки сессии.
// Читает QML-плагин MichaAI.Logind (tools/logind) — по D-Bus из своего
// потока, по сигналам, без процессов и опроса. Без плагина — пусто, и
// простой работает без оглядки на logind.
Singleton {
    id: root

    // Элемент плагина; null — плагина нет
    property var ext: null

    readonly property bool available: ext?.available ?? false
    // Что запрещено блокирующими инхибиторами: "idle", "sleep"…
    readonly property var blocked: (ext?.blocked ?? "").split(":").filter(s => s !== "")
    // Кто запрещает: [{what, who, why}]
    readonly property var inhibitors: {
        try {
            return JSON.parse(ext?.inhibitors || "[]")
        } catch (e) {
            return []
        }
    }

    // Подсказки сессии для logind и тех, кто его спрашивает
    property bool locked: false
    property bool idle: false
    // Держать delay-инхибитор сна: logind ждёт sleepReady()
    property bool guardSleep: false

    signal prepareForSleep(bool start)
    // loginctl lock-session
    signal lockRequested()

    function sleepReady() { ext?.sleepReady() }

    // Кто держит запрет what ("idle"/"sleep"): «make», «mpv»…
    function holders(what) {
        return inhibitors.filter(i => i.what.split(":").includes(what)).map(i => i.who)
    }

    Connections {
        target: root.ext
        function onPrepareForSleep(start) { root.prepareForSleep(start) }
        function onLockRequested() { root.lockRequested() }
    }

    Component.onCompleted: {
        const c = Qt.createComponent("LogindItem.qml")
        if (c.status !== Component.Ready) {
            console.info("Logind: нет плагина MichaAI.Logind — без systemd-inhibit и лока перед сном:", c.errorString())
            return
        }
        ext = c.createObject(root, {
            locked: Qt.binding(() => root.locked),
            idle: Qt.binding(() => root.idle),
            guardSleep: Qt.binding(() => root.guardSleep)
        })
    }
}
