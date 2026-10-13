import QtQuick
import ".."

// Текст с цифрами одинаковой ширины: каждая цифра в ячейке ширины
// самой широкой цифры шрифта, остальные символы — своей ширины.
// Для шрифтов без табличных цифр (Neofolia), чтобы часы не дёргались.
Row {
    id: root

    property string text: ""
    property string fontFamily: Theme.displayFont
    property real pixelSize: Theme.fontSize
    property color color: Theme.text

    FontMetrics {
        id: fm
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
    }

    readonly property real digitWidth: {
        fm.font.family // пересчёт после загрузки шрифта
        let w = 0
        for (let d = 0; d <= 9; d++)
            w = Math.max(w, fm.advanceWidth(d.toString()))
        return Math.ceil(w)
    }

    Repeater {
        model: root.text.length

        Text {
            required property int index
            readonly property bool digit: text >= "0" && text <= "9"

            width: digit ? root.digitWidth : implicitWidth
            horizontalAlignment: Text.AlignHCenter
            text: root.text.charAt(index)
            font.family: root.fontFamily
            font.pixelSize: root.pixelSize
            color: root.color
        }
    }
}
