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
    Component.onCompleted: {
        sync()
        takeMeta(true)
    }

    Timer {
        interval: root.switchDelay
        running: root.switchLater
        onTriggered: root.held = root.candidate
    }

    readonly property MprisPlayer active: held

    readonly property bool playing: active?.isPlaying ?? false
    readonly property string title: meta.title || "Ничего не играет"
    readonly property string artist: meta.artist
    readonly property string album: meta.album

    // Метаданные без провалов: на смене трека плеер на миг отдаёт пустое
    // название и обложку, и всё мигало «Ничего не играет». Пока плеер тот
    // же, пустое ждём metaGrace — обычно за это время приходит новое.
    // Другой плеер — сразу. Обложку — отдельно: её присылают и позже
    readonly property int metaGrace: 1500
    readonly property var raw: ({
        title: active?.trackTitle ?? "",
        artist: active?.trackArtist ?? "",
        album: active?.trackAlbum ?? "",
        length: Math.round(active?.length ?? 0),
        art: active?.trackArtUrl ?? ""
    })
    property var meta: ({ title: "", artist: "", album: "", length: 0 })
    property string artUrl: ""
    property MprisPlayer metaOf: null

    function takeMeta(force) {
        const same = active === metaOf
        metaOf = active
        if (force || !same || raw.title !== "") {
            metaGap.stop()
            meta = { title: raw.title, artist: raw.artist, album: raw.album, length: raw.length }
        } else {
            metaGap.restart()
        }
        if (force || !same || raw.art !== "") {
            artGap.stop()
            artUrl = raw.art
        } else if (artUrl !== "") {
            artGap.restart()
        }
    }
    onRawChanged: takeMeta(false)
    Timer { id: metaGap; interval: root.metaGrace; onTriggered: root.takeMeta(true) }
    Timer { id: artGap; interval: root.metaGrace; onTriggered: root.artUrl = root.raw.art }

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
