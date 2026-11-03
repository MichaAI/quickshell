pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property string sinkName: sink?.description || sink?.nickname || sink?.name || "—"

    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? false
    readonly property string sourceName: source?.description || source?.nickname || source?.name || "—"

    // Аудио-потоки приложений (для микшера).
    // Фильтруем ТОЛЬКО по n.type: это CONSTANT-свойство, заполняемое при создании
    // объекта в реестре. Опираться здесь на n.properties нельзя — они существуют
    // лишь пока нода привязана (bound), а привязкой управляет PwObjectTracker,
    // подписанный на этот же список. Получается петля биндинга: нода
    // привязывается -> появляется media.class -> выпадает из фильтра ->
    // отвязывается -> properties очищаются -> снова попадает в фильтр. Отвязка
    // при этом происходит прямо внутри обработки pipewire-события, после чего
    // quickshell дёргает pw_node_enum_params() на уже уничтоженном proxy и падает
    // с SIGSEGV. Ловилось на Stream/Input/Audio (микрофон в OBS и т.п.).
    readonly property var streams: Pipewire.nodes.values // qmllint disable missing-property
        .filter(n => n.type === PwNodeType.AudioOutStream)

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property string icon: {
        if (muted) return "󰝟"
        if (volume < 0.34) return "󰕿"
        if (volume < 0.67) return "󰖀"
        return "󰕾"
    }

    function setVolume(v) {
        if (sink?.ready && sink?.audio) {
            sink.audio.muted = false
            sink.audio.volume = Math.max(0, Math.min(1, v))
        }
    }

    function change(delta) {
        setVolume(volume + delta)
    }

    function toggleMute() {
        if (sink?.ready && sink?.audio)
            sink.audio.muted = !sink.audio.muted
    }

    function toggleMicMute() {
        if (source?.ready && source?.audio)
            source.audio.muted = !source.audio.muted
    }

    function setMicVolume(v) {
        if (source?.ready && source?.audio)
            source.audio.volume = Math.max(0, Math.min(1, v))
    }

    function streamName(node) {
        return node.properties?.["application.name"]
            || node.properties?.["node.name"]
            || node.description
            || node.name
    }
}
