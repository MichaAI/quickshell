pragma Singleton
import Quickshell
import QtQuick

// Расширение плеера org.mpris.MediaPlayer2.MichaAIext (на объекте MPRIS):
// две кнопки со своими SVG (Left/Right) и текст песни в LRC. Читает его
// QML-плагин MichaAI.Mpris (tools/mprisext) — по D-Bus из своего потока,
// по сигналам PropertiesChanged, без процессов и опроса.
Singleton {
    id: root

    // Элемент плагина; null — плагина нет
    property var ext: null

    readonly property bool available: ext?.available ?? false
    readonly property string leftIcon: ext?.leftIcon ?? ""
    readonly property string rightIcon: ext?.rightIcon ?? ""

    // Текст от плеера (LRC); плагин отдаёт его, только если он для трека,
    // который играет сейчас
    readonly property string lyrics: ext?.lyrics ?? ""

    function left() { ext?.left() }
    function right() { ext?.right() }

    // SVG как картинка: currentColor — цвет кнопки
    function icon(svg, color) {
        if (svg === "")
            return ""
        return "data:image/svg+xml;utf8," + encodeURIComponent(svg.replace(/currentColor/g, String(color)))
    }

    Component.onCompleted: {
        const c = Qt.createComponent("MprisExtItem.qml")
        if (c.status !== Component.Ready) {
            console.info("PlayerExt: нет плагина MichaAI.Mpris — расширения плеера выключены:", c.errorString())
            return
        }
        ext = c.createObject(root, { service: Qt.binding(() => Players.active?.dbusName ?? "") })
    }
}
