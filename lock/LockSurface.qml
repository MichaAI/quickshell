import QtQuick
import Quickshell
import Quickshell.Widgets
import ".."
import "../services"
import "../components"

// Содержимое экрана блокировки на одном мониторе. Состояние — в ctx (Lock).
// Бенто из двух колонок, разбитых на разной высоте:
//   слева  — 3D-ава (квадрат) и музыка под ней,
//   справа — часы и плитка пароля с раскладкой и Caps Lock.
Item {
    id: root

    required property var ctx

    readonly property int gap: 12
    readonly property int colW: 340
    readonly property int clockH: 200
    readonly property int musicH: 100
    // Обе колонки одной высоты: квадрат + музыка = часы + пароль
    readonly property int totalH: colW + gap + musicH

    component Tile: Rectangle {
        id: tile
        // Порядок появления: плитки выпрыгивают пружиной одна за другой
        property int order: 0
        radius: 22
        color: Theme.crust
        border.width: 1
        border.color: Theme.surface0
        clip: true

        scale: 0.92
        opacity: 0
        Component.onCompleted: appear.start()
        SequentialAnimation {
            id: appear
            PauseAnimation { duration: tile.order * 60 }
            ParallelAnimation {
                Spring { target: tile; property: "scale"; to: 1; epsilon: 0.002 }
                NumberAnimation { target: tile; property: "opacity"; to: 1; duration: 180 }
            }
        }
    }

    component Btn: Text {
        id: btn
        signal pressed()
        width: 34; height: 34
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.font
        font.pixelSize: 20
        color: ma.containsMouse ? Theme.text : Theme.subtext0
        scale: ma.pressed ? 0.85 : 1
        Behavior on scale { Spring { epsilon: 0.002 } }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.pressed()
        }
    }

    component Badge: Rectangle {
        property alias text: label.text
        property color fg: Theme.lavender
        width: label.implicitWidth + 22
        height: 28
        radius: 14
        color: Theme.alpha(fg, 0.14)

        Text {
            id: label
            anchors.centerIn: parent
            font.family: Theme.font
            font.pixelSize: 12
            font.bold: true
            color: parent.fg
        }
    }

    // Фон: градиент темы с лёгким зерном
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.base }
            GradientStop { position: 1; color: Theme.crust }
        }
    }
    Image {
        anchors.fill: parent
        source: "../assets/noise.png"
        fillMode: Image.Tile
        opacity: 0.03
    }

    // Невидимый ввод пароля: точки рисуем сами
    TextInput {
        id: input
        visible: false
        focus: true
        echoMode: TextInput.Password
        enabled: !root.ctx.busy
        onTextChanged: if (root.ctx.text !== text) root.ctx.text = text
        Keys.onReturnPressed: root.ctx.submit()
        Keys.onEnterPressed: root.ctx.submit()
        Keys.onEscapePressed: text = ""

        Connections {
            target: root.ctx
            function onTextChanged() {
                if (input.text !== root.ctx.text)
                    input.text = root.ctx.text
            }
        }
    }
    Component.onCompleted: input.forceActiveFocus()

    Row {
        anchors.centerIn: parent
        spacing: root.gap

        // ===== Левая колонка =====
        Column {
            spacing: root.gap

            // --- 3D-ава ---
            // ~/avatar.* в 3D, если есть модель и QtQuick3D; иначе ~/.face;
            // иначе инициал пользователя
            Tile {
                order: 0
                width: root.colW
                height: root.colW

                Loader {
                    id: model3d
                    anchors.fill: parent
                    readonly property bool shown: status === Loader.Ready && item.ready
                    active: root.ctx.avatarModel !== ""
                    visible: shown
                    source: "Avatar3D.qml"
                    onLoaded: item.model = Qt.binding(() => "file://" + root.ctx.avatarModel)
                }

                ClippingRectangle {
                    anchors.centerIn: parent
                    width: 160; height: 160
                    radius: 80
                    color: Theme.surface0
                    visible: !model3d.shown

                    Image {
                        id: faceImg
                        anchors.fill: parent
                        source: "file://" + root.ctx.home + "/.face"
                        sourceSize: Qt.size(320, 320)
                        fillMode: Image.PreserveAspectCrop
                    }
                    GradientText {
                        anchors.centerIn: parent
                        visible: faceImg.status !== Image.Ready
                        display: true
                        pixelSize: 72
                        text: root.ctx.user.charAt(0).toUpperCase()
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 16
                    text: root.ctx.user
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.overlay1
                }
            }

            // --- Музыка ---
            Tile {
                order: 2
                width: root.colW
                height: root.musicH

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    spacing: 12

                    ClippingRectangle {
                        width: 64; height: 64
                        radius: 14
                        color: Theme.surface0
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            anchors.fill: parent
                            source: Players.active?.trackArtUrl ?? ""
                            sourceSize: Qt.size(128, 128)
                            fillMode: Image.PreserveAspectCrop
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !Players.active
                            text: "󰝚"
                            font.family: Theme.font
                            font.pixelSize: 24
                            color: Theme.surface2
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.colW - 16 - 64 - 12 - (Players.active ? controls.width + 12 : 0) - 16
                        spacing: 3

                        GradientText {
                            width: parent.width
                            pixelSize: 14
                            maxChars: 22
                            text: Players.title
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: Players.artist
                            visible: text !== ""
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.subtext1
                        }
                    }

                    Row {
                        id: controls
                        visible: Players.active !== null
                        anchors.verticalCenter: parent.verticalCenter

                        Btn {
                            text: "󰒮"
                            onPressed: Players.active?.previous()
                        }
                        Btn {
                            text: Players.playing ? "󰏤" : "󰐊"
                            color: Theme.mauve
                            onPressed: Players.active?.togglePlaying()
                        }
                        Btn {
                            text: "󰒭"
                            onPressed: Players.active?.next()
                        }
                    }
                }
            }
        }

        // ===== Правая колонка =====
        Column {
            spacing: root.gap

            // --- Часы ---
            Tile {
                order: 1
                width: root.colW
                height: root.clockH

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    GradientText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        display: true
                        pixelSize: 96
                        outlineWidth: 4
                        outlineColor: Theme.base
                        text: Qt.formatDateTime(Time.now, "HH:mm")
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            const d = Time.dateLong
                            return d.charAt(0).toUpperCase() + d.slice(1)
                        }
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.subtext0
                    }
                }
            }

            // --- Пароль ---
            Tile {
                order: 3
                width: root.colW
                height: root.totalH - root.clockH - root.gap

                // Раскладка — слева сверху. Смена — пинок: значок
                // подпрыгивает и пружинит обратно
                Badge {
                    id: langBadge
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 18
                    text: "󰌌  " + (Niri.langShort || "—")
                    fg: Theme.lavender

                    property real kick: 0
                    transform: Translate { y: -langBadge.kick }
                    scale: 1 + langBadge.kick / 40

                    SpringAnimation {
                        id: kickAnim
                        target: langBadge; property: "kick"; to: 0
                        spring: 6; damping: 0.18; epsilon: 0.05
                    }
                    Connections {
                        target: Niri
                        function onLangShortChanged() {
                            langBadge.kick = 8
                            kickAnim.restart()
                        }
                    }
                }

                // Caps Lock — справа сверху, выпрыгивает пружиной
                Badge {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    text: "󰘲  CAPS"
                    fg: Theme.peach
                    scale: root.ctx.caps ? 1 : 0
                    visible: scale > 0.01
                    Behavior on scale { Spring { epsilon: 0.002 } }
                }

                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 14
                    anchors.margins: 18
                    height: 50

                    Rectangle {
                        id: field
                        width: parent.width
                        height: parent.height
                        radius: 25
                        color: Theme.base
                        border.width: 2
                        border.color: root.ctx.error !== "" ? Theme.red
                                    : root.ctx.busy ? Theme.surface2 : Theme.mauve
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        // Тряска при ошибке: пинок вбок, пружина почти без затухания
                        property real shake: 0
                        x: shake
                        SpringAnimation {
                            id: shakeAnim
                            target: field; property: "shake"; to: 0
                            spring: 14; damping: 0.12; epsilon: 0.2
                        }
                        Connections {
                            target: root.ctx
                            function onFailsChanged() {
                                field.shake = 18
                                shakeAnim.restart()
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.ctx.text === "" && !root.ctx.busy
                            text: root.ctx.error !== "" ? root.ctx.error : "Пароль"
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.italic: true
                            color: root.ctx.error !== "" ? Theme.red : Theme.overlay0
                        }

                        // Точки: каждая выпрыгивает пружиной
                        Row {
                            anchors.centerIn: parent
                            spacing: 7
                            Repeater {
                                model: Math.min(root.ctx.text.length, 20)

                                Rectangle {
                                    id: dot
                                    required property int index
                                    width: 9; height: 9
                                    radius: 4.5
                                    color: Theme.mix(Theme.gradStart, Theme.gradEnd,
                                                     root.ctx.text.length > 1 ? index / (Math.min(root.ctx.text.length, 20) - 1) : 0)
                                    scale: 0
                                    Component.onCompleted: scale = 1
                                    Behavior on scale { Spring { epsilon: 0.002 } }

                                    // Пока PAM думает — точки волной пульсируют
                                    SequentialAnimation on opacity {
                                        running: root.ctx.busy
                                        loops: Animation.Infinite
                                        alwaysRunToEnd: true
                                        PauseAnimation { duration: dot.index * 40 }
                                        NumberAnimation { to: 0.3; duration: 300 }
                                        NumberAnimation { to: 1; duration: 300 }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 18
                    text: "⏎ разблокировать   ·   Esc очистить"
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.overlay0
                }
            }
        }
    }
}
