pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import "../.."
import "../../services"
import "../../components"

// Лончер приложений — выпадающее меню из бара.
Item {
    id: root

    implicitWidth: 620
    implicitHeight: 480

    property string query: ""
    property int selIdx: 0

    readonly property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)

    function score(app, q) {
        const name = app.name.toLowerCase()
        if (name.startsWith(q)) return 100
        if (name.includes(q)) return 60
        if ((app.genericName ?? "").toLowerCase().includes(q)) return 30
        if ((app.comment ?? "").toLowerCase().includes(q)) return 20
        let i = 0
        for (const ch of name)
            if (ch === q[i]) i++
        return i === q.length ? 10 : 0
    }

    // Рейтинг: частота запусков (аналог кэша wofi)
    property var counts: ({})
    readonly property string histFile: Quickshell.env("HOME") + "/.cache/quickshell-launcher-hist"

    Process {
        id: histRead
        command: ["cat", root.histFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const c = {}
                for (const l of this.text.split("\n"))
                    if (l !== "") c[l] = (c[l] ?? 0) + 1
                root.counts = c
            }
        }
    }
    Process { id: histWrite }

    readonly property var results: {
        const q = query.toLowerCase().trim()
        const freq = a => counts[a.id] ?? 0
        if (q === "")
            return [...apps].sort((a, b) =>
                freq(b) - freq(a) || a.name.localeCompare(b.name))
        return apps
            .map(a => [score(a, q), a])
            .filter(x => x[0] > 0)
            .sort((x, y) => (y[0] + freq(y[1]) * 5) - (x[0] + freq(x[1]) * 5)
                || x[1].name.localeCompare(y[1].name))
            .map(x => x[1])
    }

    onResultsChanged: selIdx = 0
    Component.onCompleted: {
        searchInput.forceActiveFocus()
        histRead.running = true
    }

    function launch() {
        const app = results[selIdx]
        if (app) {
            histWrite.exec(["sh", "-c", 'printf "%s\\n" "$1" >> "$2"', "qs", app.id, root.histFile])
            app.execute()
            Ui.closePopouts()
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        anchors.bottomMargin: 10
        spacing: 10

        // Поиск
        Item {
            width: parent.width
            height: 36

            Text {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍉"
                font.family: Theme.font
                font.pixelSize: 16
                color: Theme.mauve
            }

            TextInput {
                id: searchInput
                anchors.left: searchIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font
                font.pixelSize: 16
                color: Theme.text
                selectionColor: Theme.surface1
                clip: true

                onTextChanged: root.query = text

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        Ui.closePopouts()
                        event.accepted = true
                        break
                    case Qt.Key_Down:
                        root.selIdx = Math.min(root.selIdx + 1, root.results.length - 1)
                        event.accepted = true
                        break
                    case Qt.Key_Up:
                        root.selIdx = Math.max(0, root.selIdx - 1)
                        event.accepted = true
                        break
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.launch()
                        event.accepted = true
                        break
                    }
                }

                Text {
                    anchors.fill: parent
                    visible: searchInput.text === ""
                    text: "Поиск приложений…"
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.italic: true
                    color: Theme.overlay0
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // Градиентный разделитель
        Rectangle {
            width: parent.width
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.alpha(Theme.gradStart, 0.6) }
                GradientStop { position: 1; color: Theme.alpha(Theme.gradEnd, 0.6) }
            }
        }

        ListView {
            id: list
            width: parent.width
            height: parent.height - 36 - 1 - 20 - 20
            clip: true
            model: root.results
            currentIndex: root.selIdx
            boundsBehavior: Flickable.StopAtBounds

            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                readonly property bool selected: index === root.selIdx

                width: list.width
                height: 46
                radius: 10
                color: selected ? Theme.cardBg
                     : rma.containsMouse ? Theme.alpha(Theme.cardBg, 0.5) : "transparent"

                Rectangle {
                    visible: row.selected
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 24
                    radius: 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.gradStart }
                        GradientStop { position: 1; color: Theme.gradEnd }
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 28
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        GradientText {
                            visible: row.selected
                            pixelSize: 14
                            maxChars: 48
                            text: row.modelData.name
                        }
                        Text {
                            visible: !row.selected
                            text: row.modelData.name
                            font.family: Theme.font
                            font.pixelSize: 14
                            color: Theme.text
                        }
                        Text {
                            visible: (row.modelData.genericName ?? "") !== ""
                                || (row.modelData.comment ?? "") !== ""
                            width: list.width - 80
                            text: row.modelData.genericName || row.modelData.comment || ""
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.overlay1
                        }
                    }
                }

                MouseArea {
                    id: rma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selIdx = row.index
                        root.launch()
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.results.length + " приложений   ·   ↑↓ навигация   ·   ⏎ запуск   ·   Esc закрыть"
            font.family: Theme.font
            font.pixelSize: 10
            color: Theme.overlay0
        }
    }
}
