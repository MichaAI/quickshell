pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: root

    property MprisPlayer selected: null

    readonly property var list: Mpris.players.values

    readonly property MprisPlayer active: {
        if (selected && list.includes(selected))
            return selected
        return list.find(p => p.isPlaying)
            ?? list.find(p => (p.trackTitle ?? "") !== "")
            ?? (list.length > 0 ? list[0] : null)
    }

    readonly property bool playing: active?.isPlaying ?? false
    readonly property string title: active?.trackTitle || "Ничего не играет"
    readonly property string artist: active?.trackArtist || ""

    // Тикаем позицию, пока что-то играет
    Timer {
        interval: 1000
        running: root.playing
        repeat: true
        onTriggered: root.active.positionChanged()
    }

    function fmt(sec) {
        if (isNaN(sec) || sec < 0) return "0:00"
        const m = Math.floor(sec / 60)
        const s = Math.floor(sec % 60)
        return `${m}:${s < 10 ? "0" : ""}${s}`
    }

    readonly property string timeText: active
        ? fmt(active.position) + "/" + fmt(active.length)
        : ""
}
