pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: root

    // playerctld — не плеер, а зеркало последнего активного (для
    // playerctl на горячих клавишах): в списке он двойник настоящего
    readonly property var list: Mpris.players.values.filter(p => p.dbusName !== "org.mpris.MediaPlayer2.playerctld")

    // Кого показывать, если показанного нет (закрыли) или на старте
    function fallback() {
        return list.find(p => p.isPlaying)
            ?? list.find(p => (p.trackTitle ?? "") !== "")
            ?? (list.length > 0 ? list[0] : null)
    }

    // Показанный плеер. Правила:
    //  · выбрали руками — сразу он;
    //  · другой заиграл (был тихим, стал играть) — сразу он, последний
    //    заигравший главнее; только мигнувший (меньше startDelay) не в счёт;
    //  · показанный замолчал, а другой уже играл — переходим через
    //    stopDelay: пауза между треками плеер не дёргает;
    //  · не играет никто — остаёмся на последнем;
    //  · показанный закрыли — сразу на fallback().
    readonly property int startDelay: 400
    readonly property int stopDelay: 1500
    property MprisPlayer held: null
    readonly property MprisPlayer active: held

    // Руками: выбор из попаута
    function select(p) {
        if (p && list.includes(p)) {
            starting = null
            held = p
        }
    }

    // Кто играет сейчас; новые в этом списке — «заиграли»
    readonly property var playingList: list.filter(p => p.isPlaying)
    property var wasPlaying: []
    property MprisPlayer starting: null
    onPlayingListChanged: {
        const now = playingList
        const fresh = now.filter(p => !wasPlaying.includes(p) && p !== held)
        wasPlaying = now
        if (fresh.length > 0) {
            starting = fresh[fresh.length - 1]
            startTimer.restart()
        }
    }
    Timer {
        id: startTimer
        interval: root.startDelay
        onTriggered: {
            const p = root.starting
            root.starting = null
            if (p && p !== root.held && root.list.includes(p) && p.isPlaying)
                root.held = p
        }
    }

    // Показанный молчит, а кто-то другой играет — перейти чуть погодя
    readonly property bool heldSilent: held !== null && list.includes(held) && !held.isPlaying
        && playingList.some(p => p !== held)
    Timer {
        interval: root.stopDelay
        running: root.heldSilent
        onTriggered: {
            const others = root.playingList.filter(p => p !== root.held)
            if (root.heldSilent && others.length > 0)
                root.held = others[others.length - 1]
        }
    }

    // Показанный пропал (или его ещё нет) — сразу кого-то другого
    onListChanged: {
        if (held === null || !list.includes(held))
            held = fallback()
    }
    Component.onCompleted: {
        wasPlaying = playingList
        held = fallback()
        takeMeta(true)
    }

    readonly property bool playing: active?.isPlaying ?? false
    readonly property string title: meta.title || "Ничего не играет"
    readonly property string artist: meta.artist
    readonly property string album: meta.album

    // Метаданные меняются разом — название, исполнитель, альбом и обложка
    // одновременно, чтобы смена трека была одним переходом. На смене
    // трека плеер сначала на миг отдаёт пустое название, а обложку часто
    // присылает отдельно и позже. Поэтому, пока плеер тот же:
    //  · пустое название — ждём до metaGrace, держим прежнее;
    //  · новое название без новой обложки — ждём обложку до artWait,
    //    потом берём что есть;
    //  · новая обложка — сразу всё.
    // Другой плеер — сразу всё
    readonly property int metaGrace: 1500
    readonly property int artWait: 700
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

    function commit() {
        metaWait.stop()
        const r = raw
        meta = { title: r.title, artist: r.artist, album: r.album, length: r.length }
        artUrl = r.art
    }

    function takeMeta(force) {
        const same = active === metaOf
        metaOf = active
        const r = raw
        if (force || !same) return commit()
        const newArt = r.art !== "" && r.art !== artUrl
        if (r.title === "") {
            // Пустое: держим прежнее, если было что держать
            if (meta.title === "" && !newArt) return commit()
            if (!metaWait.running) { metaWait.interval = metaGrace; metaWait.start() }
            return
        }
        const newTrack = r.title !== meta.title || r.artist !== meta.artist
        if (!newTrack) {
            // Тот же трек: обложка пришла позже, длина уточнилась…
            if (r.art === "" && artUrl !== "") {
                if (!metaWait.running) { metaWait.interval = metaGrace; metaWait.start() }
                meta = { title: r.title, artist: r.artist, album: r.album, length: r.length }
                return
            }
            return commit()
        }
        if (newArt || artUrl === "") return commit()
        // Новый трек, а обложка ещё старая или пустая — подождать её
        if (!metaWait.running || metaWait.interval !== artWait) {
            metaWait.interval = artWait
            metaWait.restart()
        }
    }
    onRawChanged: takeMeta(false)
    Timer { id: metaWait; onTriggered: root.commit() }

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
