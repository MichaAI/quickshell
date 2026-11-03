pragma Singleton
import Quickshell
import QtQuick
import "../config"

// OSD громкости, микрофона и яркости: что показать и когда. Сам OSD
// выезжает из-под бара (bar/Bar.qml, components/OsdContent.qml).
// Молчит первые секунды после запуска, сразу после смены выхода/входа
// (у нового устройства своя громкость — это не изменение) и пока открыт
// попаут: там значение и так видно.
Singleton {
    id: root

    property string kind: "volume"      // volume | mic | brightness
    property bool shown: false

    readonly property real value: kind === "volume" ? Audio.volume
        : kind === "mic" ? Audio.micVolume : Brightness.value
    readonly property bool muted: kind === "volume" ? Audio.muted
        : kind === "mic" ? Audio.micMuted : false
    readonly property string icon: kind === "volume" ? Audio.icon
        : kind === "mic" ? (Audio.micMuted ? "󰍭" : "󰍬") : Brightness.icon
    readonly property color color: kind === "volume" ? Theme.mauve
        : kind === "mic" ? Theme.peach : Theme.yellow

    function show(k) {
        if (k !== "volume" && k !== "mic" && k !== "brightness")
            return
        kind = k
        shown = true
        hide.restart()
    }

    function changed(k) {
        if (!ready.done || quiet.running || Ui.openPopouts > 0)
            return
        show(k)
    }

    Timer {
        id: ready
        property bool done: false
        running: true
        interval: 2000
        onTriggered: done = true
    }
    Timer { id: quiet; interval: 500 }
    Timer {
        id: hide
        interval: 1500
        onTriggered: root.shown = false
    }

    // Открыли попаут — OSD уступает место
    Connections {
        target: Ui
        function onOpenPopoutsChanged() {
            if (Ui.openPopouts > 0)
                root.shown = false
        }
    }

    Connections {
        target: Audio
        function onVolumeChanged() { root.changed("volume") }
        function onMutedChanged() { root.changed("volume") }
        function onMicVolumeChanged() { root.changed("mic") }
        function onMicMutedChanged() { root.changed("mic") }
        function onSinkChanged() { quiet.restart() }
        function onSourceChanged() { quiet.restart() }
    }

    Connections {
        target: Brightness
        function onRawChanged() { root.changed("brightness") }
    }
}
