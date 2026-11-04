import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"

// Строка результата лончера: иконка (приложение / образец цвета /
// превью из буфера / глиф), заголовок, подпись, подсказка клавиш.
// У калькулятора с plot(…) под строкой ещё и график, у QR — картинка
// (qr: матрица для QrView), у гифок — анимация вместо иконки (thumbUrl:
// качается curl'ом в кэш, чтобы шла через тот же прокси).
Rectangle {
    id: row
    required property var modelData
    required property int index

    property bool selected: false

    // Клик: shift — средней кнопкой или с Shift (как ⇧⏎)
    signal activated(bool shift)

    readonly property bool big: modelData.big ?? false
    readonly property bool hasPlot: modelData.plot !== undefined
    readonly property bool hasPreview: (modelData.qr ?? null) !== null
    readonly property bool hasThumb: (modelData.thumbUrl ?? "") !== ""
    // Заголовок с разметкой (имена линий графика их цветами) — без градиента
    readonly property bool richTitle: (modelData.titleRich ?? "") !== ""

    height: hasPlot ? 220 : hasPreview ? 46 + 210 : hasThumb ? 84 : big ? 60 : 46
    radius: 10
    color: selected ? Theme.cardBg
         : rma.containsMouse ? Theme.alpha(Theme.cardBg, 0.5) : "transparent"

    // Верхняя строка (у графика под ней ещё сам график)
    Item {
        id: header
        width: parent.width
        height: row.hasPlot || row.hasPreview ? 46 : row.height
    }

    // QR под строкой — в стиле шелла
    QrView {
        visible: row.hasPreview
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.leftMargin: 14
        width: 200
        height: 200
        matrix: row.modelData.qr ?? []
    }

    // Над MouseArea строки: иначе та забирает наведение и значений под
    // курсором не видно. Клики график не ловит — они уходят строке
    PlotView {
        z: 1
        visible: row.hasPlot
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        anchors.topMargin: 0
        plot: row.modelData.plot ?? null
        titleLegend: row.richTitle
    }

    Rectangle {
        visible: row.selected
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: header.verticalCenter
        width: 3
        height: row.big ? 34 : 24
        radius: 2
        gradient: OkGradient {
            from: Theme.gradStart
            to: Theme.gradEnd
        }
    }

    // Иконка: картинка приложения / образец цвета / превью из буфера / глиф
    Item {
        id: iconBox
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: header.verticalCenter
        width: row.hasThumb ? 112 : row.big ? 36 : 28
        height: row.hasThumb ? 68 : width

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
            visible: (row.modelData.glyph ?? "") !== "" && !clipThumb.visible && !gifThumb.visible
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

    // Гифка: скачать в кэш и крутить
    AnimatedImage {
        id: gifThumb
        parent: iconBox
        anchors.fill: parent
        visible: status === AnimatedImage.Ready
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        playing: visible
        property string file: ""
        source: file !== "" ? "file://" + file : ""

        Process {
            id: fetch
            property string target: ""
            onExited: (code, _s) => { if (code === 0) gifThumb.file = fetch.target }
        }

        Component.onCompleted: {
            const url = row.modelData.thumbUrl ?? ""
            if (url === "") return
            const dir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
            fetch.target = dir + "/qs-gif/" + Qt.md5(url) + "." + (url.match(/\.(gif|webp)(\?|$)/)?.[1] ?? "gif")
            fetch.exec(["sh", "-c",
                't=$1; shift; mkdir -p "${t%/*}" && { [ -s "$t" ] || { "$@" -o "$t.part" && mv "$t.part" "$t"; }; }',
                "qs", fetch.target, ...Tools.curl([url])])
        }
    }

    Column {
        anchors.left: iconBox.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: badge.shown ? badge.implicitWidth + 20 : 12
        anchors.verticalCenter: header.verticalCenter
        // Над полосой прогресса — чуть выше, чтобы подпись её не задевала
        anchors.verticalCenterOffset: isNaN(row.modelData.progress ?? NaN) ? 0 : -3
        spacing: 1

        GradientText {
            visible: row.selected && !row.big && !row.richTitle
            pixelSize: 14
            maxChars: 56
            text: row.modelData.title ?? ""
        }
        Text {
            visible: !row.selected || row.big || row.richTitle
            width: parent.width
            text: row.richTitle ? row.modelData.titleRich : row.modelData.title ?? ""
            textFormat: row.richTitle ? Text.StyledText : Text.PlainText
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

    // Прогресс (закачка nix, поиск, уровни): доля 0…1, -1 — сколько всего,
    // неизвестно; progressTarget — куда значение поменяется по ⏎
    ProgressBar {
        readonly property real v: row.modelData.progress ?? NaN
        visible: !isNaN(v)
        value: isNaN(v) ? 0 : v
        target: row.modelData.progressTarget ?? NaN
        wavy: row.modelData.progressWavy ?? false
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: header.bottom
        anchors.leftMargin: 54
        anchors.rightMargin: 14
        anchors.bottomMargin: 3
        height: 4
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
