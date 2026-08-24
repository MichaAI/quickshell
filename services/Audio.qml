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

    // Аудио-потоки приложений (для микшера)
    readonly property var streams: Pipewire.nodes.values.filter(n => {
        if (!n.isStream) return false
        const mc = n.properties?.["media.class"] ?? ""
        return mc === "" || mc.startsWith("Stream/Output")
    })

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
