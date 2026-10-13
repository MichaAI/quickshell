import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../../config"
import "../../../components"

// Строка результата лончера: иконка (приложение / образец цвета /
// превью из буфера / глиф), заголовок, подпись, подсказка клавиш.
// У калькулятора с plot(…) под строкой ещё и график.
Rectangle {
    id: row
    required property var modelData
    required property int index

    property bool selected: false

    // Клик: shift — средней кнопкой или с Shift (как ⇧⏎)
    signal activated(bool shift)

    readonly property bool big: modelData.big ?? false
    readonly property bool hasPlot: modelData.plot !== undefined

    height: hasPlot ? 220 : big ? 60 : 46
    radius: 10
    color: selected ? Theme.cardBg
         : rma.containsMouse ? Theme.alpha(Theme.cardBg, 0.5) : "transparent"

    // Верхняя строка (у графика под ней ещё сам график)
    Item {
        id: header
        width: parent.width
        height: row.hasPlot ? 46 : row.height
    }

    PlotView {
        visible: row.hasPlot
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        anchors.topMargin: 0
        plot: row.modelData.plot ?? null
    }

    Rectangle {
        visible: row.selected
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: header.verticalCenter
        width: 3
        height: row.big ? 34 : 24
        radius: 2
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.gradStart }
            GradientStop { position: 1; color: Theme.gradEnd }
        }
    }

    // Иконка: картинка приложения / образец цвета / превью из буфера / глиф
    Item {
        id: iconBox
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: header.verticalCenter
        width: row.big ? 36 : 28
        height: width

        // Путь к иконке ищем только для строк на экране,
        // а не для всех приложений разом
        IconImage {
            anchors.fill: parent
            visible: row.modelData.iconName !== undefined
            implicitSize: parent.width
            source: visible
                ? Quickshell.iconPath(row.modelData.iconName, "application-x-executable") : ""
        }

        Rectangle {
            anchors.fill: parent
            visible: row.modelData.swatch !== undefined
            radius: 8
            color: row.modelData.swatch ?? "transparent"
            border.width: 1
            border.color: Theme.surface1
        }

        Text {
            anchors.centerIn: parent
            visible: (row.modelData.glyph ?? "") !== "" && !clipThumb.visible
            text: row.modelData.glyph ?? ""
            font.family: Theme.font
            font.pixelSize: row.modelData.glyphSize ?? (row.big ? 22 : 18)
            color: row.modelData.glyphColor ?? Theme.mauve
        }

        // Превью картинки из cliphist — декодируем лениво в кэш
        Image {
            id: clipThumb
            anchors.fill: parent
            visible: status === Image.Ready
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 64
            sourceSize.height: 64
            property string file: ""
            source: file !== "" ? "file://" + file : ""

            Process {
                id: decode
                property string target: ""
                onExited: (code, _s) => { if (code === 0) clipThumb.file = decode.target }
            }

            Component.onCompleted: {
                const line = row.modelData.clipImage ?? ""
                if (line === "") return
                const id = line.slice(0, line.indexOf("\t"))
                const dir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
                decode.target = dir + "/qs-cliphist/" + id + "." + row.modelData.clipExt
                decode.exec(["sh", "-c",
                    'mkdir -p "${2%/*}" && { [ -s "$2" ] || printf "%s" "$1" | cliphist decode > "$2"; }',
                    "qs", line, decode.target])
            }
        }
    }

    Column {
        anchors.left: iconBox.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: badge.shown ? badge.implicitWidth + 20 : 12
        anchors.verticalCenter: header.verticalCenter
        spacing: 1

        GradientText {
            visible: row.selected && !row.big
            pixelSize: 14
            maxChars: 56
            text: row.modelData.title ?? ""
        }
        Text {
            visible: !row.selected || row.big
            width: parent.width
            text: row.modelData.title ?? ""
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: row.big ? 20 : 14
            font.weight: row.big ? Font.DemiBold : Font.Normal
            color: Theme.text
        }
        Text {
            visible: (row.modelData.sub ?? "") !== ""
            width: parent.width
            text: row.modelData.sub ?? ""
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 11
            color: row.modelData.subColor ?? Theme.overlay1
        }
    }

    Text {
        id: badge
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: header.verticalCenter
        readonly property bool shown: row.selected || rma.containsMouse
        visible: shown
        text: row.modelData.badge ?? ""
        font.family: Theme.font
        font.pixelSize: 10
        color: Theme.overlay0
    }

    MouseArea {
        id: rma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => row.activated(event.button === Qt.MiddleButton
            || (event.modifiers & Qt.ShiftModifier))
    }
}
