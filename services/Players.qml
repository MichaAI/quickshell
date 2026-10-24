pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: root

    property MprisPlayer selected: null

    // playerctld — не плеер, а зеркало последнего активного (для
    // playerctl на горячих клавишах): в списке он двойник настоящего
    readonly property var list: Mpris.players.values.filter(p => p.dbusName !== "org.mpris.MediaPlayer2.playerctld")

    // Кого показали бы прямо сейчас, без гистерезиса
    readonly property MprisPlayer candidate: {
        if (selected && list.includes(selected))
            return selected
        return list.find(p => p.isPlaying)
            ?? list.find(p => (p.trackTitle ?? "") !== "")
            ?? (list.length > 0 ? list[0] : null)
    }

    // Гистерезис: когда показанный плеер встаёт на паузу, на другой,
    // играющий, переходим не сразу, а через switchDelay — пауза между
    // треками или короткий звук из браузера плеер не дёргают. Если не
    // играет никто — остаёмся на последнем
    readonly property int switchDelay: 3000
    property MprisPlayer held: null
    readonly property bool heldAlive: held !== null && list.includes(held)

    // С задержкой: показанный замолчал, а другой играет
    readonly property bool switchLater: candidate !== held && heldAlive
        && !held.isPlaying && (candidate?.isPlaying ?? false)

    // Сразу: плеер пропал или его выбрали руками. Функцией, а не
    // свойством с onChanged: из обработчика производные свойства видны
    // ещё старыми, а флаг, сброшенный в собственном onChanged, залипал
    // и следующий выбор руками не срабатывал
    function sync() {
        if (candidate === held)
            return
        const alive = held !== null && list.includes(held)
        if (!alive || (selected !== null && candidate === selected))
            held = candidate
    }
    onCandidateChanged: sync()
    onListChanged: sync()
    onSelectedChanged: sync()
    Component.onCompleted: sync()

    Timer {
        interval: root.switchDelay
        running: root.switchLater
        onTriggered: root.held = root.candidate
    }

    readonly property MprisPlayer active: held

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
