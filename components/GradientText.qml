import QtQuick
import "../config"

// Текст с горизонтальным градиентом from → to, смешанным в OkLab, как
// Theme.mix. По умолчанию — italic и градиент #f38ba8 -> #cba6f7.
// display: true — дисплейный шрифт (Theme.displayFont), прямой и без жирности.
// outlineWidth > 0 подкладывает под весь текст обводку outlineColor.
//
// Один Text белым → текстура → шейдер gradtext красит альфу и рисует
// обводку. Раньше каждая буква была своим Text своего цвета: Qt не сливает
// такие в одну отрисовку, и название трека стоило десятки батчей на
// каждом кадре, а обводка — ещё до 24 копий каждой буквы. Цвет — тот же,
// что был у букв: from в центре первой, to в центре последней (только
// теперь плавный, а не ступеньками по буквам). Лигатуры и кернинг
// выключены — буквы стоят там же, где стояли по одной.
Item {
    id: root

    property string text: ""
    property int maxChars: 0            // 0 = без ограничения
    property real pixelSize: Theme.fontSize
    property bool display: false
    property string fontFamily: display ? Theme.displayFont : Theme.font
    property bool italic: !display
    property int fontWeight: display ? Font.Normal : Font.DemiBold
    property color from: Theme.gradStart
    property color to: Theme.gradEnd
    property real outlineWidth: 0       // 0 = без обводки
    property color outlineColor: Theme.base

    readonly property string shown: maxChars > 0 && text.length > maxChars
        ? text.substring(0, maxChars - 1) + "…"
        : text

    // Чем толще обводка, тем больше выборок нужно, чтобы не было зазубрин.
    readonly property int outlineSteps: Math.min(24, Math.max(8, Math.ceil(outlineWidth * 4)))
    // Запас текстуры по краям: обводка и наклон курсива выходят за Text
    readonly property real pad: Math.ceil(outlineWidth + pixelSize * 0.35 + 2)

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Text {
        id: label
        text: root.shown
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        font.italic: root.italic
        font.weight: root.fontWeight
        // Как при побуквенной раскладке: без лигатур и кернинговых пар
        font.features: { "liga": 0, "calt": 0, "clig": 0, "dlig": 0 }
        font.kerning: false
        color: "white"
    }

    ShaderEffectSource {
        id: src
        sourceItem: label
        hideSource: true
        visible: false
        sourceRect: Qt.rect(-root.pad, -root.pad, label.width + 2 * root.pad, label.height + 2 * root.pad)
    }

    ShaderEffect {
        x: -root.pad
        y: -root.pad
        width: label.width + 2 * root.pad
        height: label.height + 2 * root.pad
        visible: root.shown !== ""

        readonly property real charW: root.shown.length > 0 ? label.width / root.shown.length : 0

        property variant source: src
        property size size: Qt.size(width, height)
        property real x0: root.pad + charW / 2
        property real span: root.shown.length > 1 ? label.width - charW : 0
        property real outline: root.outlineWidth
        property real steps: root.outlineSteps
        property color c0: root.from
        property color c1: root.to
        property color oc: root.outlineColor
        fragmentShader: Qt.resolvedUrl("../assets/shaders/gradtext.frag.qsb")
    }
}
