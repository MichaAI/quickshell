import QtQuick
import ".."

// Текст с горизонтальным градиентом (посимвольная интерполяция цвета).
// По умолчанию — italic и градиент #f38ba8 -> #cba6f7.
// display: true — дисплейный шрифт (Theme.displayFont), прямой и без жирности.
// outlineWidth > 0 подкладывает под весь текст обводку outlineColor
// (набор копий символа, смещённых по окружности радиуса outlineWidth).
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

    // Чем толще обводка, тем больше копий нужно, чтобы не было зазубрин.
    readonly property int outlineSteps: Math.min(24, Math.max(8, Math.ceil(outlineWidth * 4)))

    implicitWidth: glyphs.implicitWidth
    implicitHeight: glyphs.implicitHeight

    // Слой обводки целиком под слоем градиента, иначе соседние символы
    // затирали бы уже отрисованные глифы.
    Row {
        spacing: 0
        visible: root.outlineWidth > 0

        Repeater {
            model: root.outlineWidth > 0 ? root.shown.length : 0

            Item {
                required property int index

                implicitWidth: metrics.implicitWidth
                implicitHeight: metrics.implicitHeight

                Text {
                    id: metrics
                    visible: false
                    text: root.shown.charAt(parent.index)
                    font.family: root.fontFamily
                    font.pixelSize: root.pixelSize
                    font.italic: root.italic
                    font.weight: root.fontWeight
                }

                Repeater {
                    model: root.outlineSteps

                    Text {
                        required property int index
                        readonly property real angle: index * 2 * Math.PI / root.outlineSteps

                        x: Math.cos(angle) * root.outlineWidth
                        y: Math.sin(angle) * root.outlineWidth
                        text: metrics.text
                        font: metrics.font
                        color: root.outlineColor
                    }
                }
            }
        }
    }

    Row {
        id: glyphs
        spacing: 0

        Repeater {
            model: root.shown.length

            Text {
                required property int index
                text: root.shown.charAt(index)
                font.family: root.fontFamily
                font.pixelSize: root.pixelSize
                font.italic: root.italic
                font.weight: root.fontWeight
                color: root.shown.length > 1
                    ? Theme.mix(root.from, root.to, index / (root.shown.length - 1))
                    : root.from
            }
        }
    }
}
