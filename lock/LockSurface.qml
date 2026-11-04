pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell.Widgets
import "../config"
import "../services"
import "../components"

// Содержимое экрана блокировки на одном мониторе. Состояние — в ctx (Lock).
// Бенто из двух колонок, разбитых на разной высоте:
//   слева  — 3D-ава (квадрат) и музыка под ней,
//   справа — часы и плитка пароля с раскладкой и Caps Lock.
Item {
    id: root

    required property var ctx

    readonly property int gap: Settings.lockGap
    readonly property int colW: Settings.lockColumn
    readonly property int clockH: Settings.lockClockHeight
    readonly property int musicH: Settings.lockMusicHeight
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

    // Фон: размытые обои из Settings.lockWallpaper, а без них — градиент
    // темы. Сверху лёгкое зерно
    Rectangle {
        anchors.fill: parent
        gradient: OkGradient {
            from: Theme.base
            to: Theme.crust
        }
    }

    Image {
        id: wall
        anchors.fill: parent
        visible: false
        source: root.ctx.wallUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Без sourceSize и с тем же fillMode, что в Lock.qml: так картинка
        // берётся из кеша, куда её заранее загрузил Lock.qml, и не мигает
        // при блокировке
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        visible: wall.status === Image.Ready
        blurEnabled: Settings.lockWallpaperBlur > 0
        blur: 1
        blurMax: Settings.lockWallpaperBlur
    }
    Rectangle {
        anchors.fill: parent
        visible: wall.status === Image.Ready
        color: Theme.crust
        opacity: Settings.lockWallpaperDim
    }
    // Зерно против полос в размытии: одна точка шума — ровно один
    // физический пиксель, иначе при масштабе экрана оно мылится и крупнеет
    Image {
        readonly property real dpr: Screen.devicePixelRatio
        width: parent.width * dpr
        height: parent.height * dpr
        scale: 1 / dpr
        transformOrigin: Item.TopLeft
        source: "../assets/noise.png"
        fillMode: Image.Tile
        smooth: false
        opacity: Dither.lockNoise
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
        Keys.onPressed: event => {
            root.ctx.noteKey(event)
            event.accepted = false      // сам текст пусть вводит TextInput
        }

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

                // niri считает экран заблокированным только после первого кадра
                // на каждом мониторе. Ава в этом кадре (разбор модели, сцены
                // balsam'а, шейдеры Quick3D) держала лок до секунды. Поэтому
                // сначала её снимок (см. Lock.frameKey), а живая ава грузится,
                // когда экран уже закрыт, и подменяет его, когда готова
                Loader {
                    id: model3d
                    anchors.fill: parent
                    readonly property bool shown: status === Loader.Ready && (item?.ready ?? false) // qmllint disable missing-property
                    active: root.ctx.avatarModel !== "" && root.ctx.secure
                    asynchronous: true
                    // Не shown: неготовая ава должна рисоваться, чтобы Qt
                    // Quick 3D её измерил. До готовности она стоит в позе
                    // снимка под ним, а без габаритов из кеша — крошечная
                    visible: status === Loader.Ready
                    source: "Avatar3D.qml"
                    onLoaded: {
                        // Avatar3D — по строке, без типа: иначе лок зависел бы от QtQuick3D
                        // qmllint disable missing-property
                        item.bounds = Qt.binding(() => root.ctx.avatarBounds)
                        // Сцену — раньше модели: иначе RuntimeLoader успеет
                        // зря разобрать файл модели, пока сцены ещё нет
                        item.scene = Qt.binding(() => root.ctx.avatarScene !== "" ? "file://" + root.ctx.avatarScene : "")
                        item.model = Qt.binding(() => "file://" + root.ctx.avatarModel)
                        // qmllint enable missing-property
                    }
                    onShownChanged: {
                        if (shown && root.ctx.lockStarted > 0)
                            console.warn("lock: живая ава через", Date.now() - root.ctx.lockStarted, "мс после лока")
                    }
                    onStatusChanged: {
                        if (status === Loader.Error)
                            console.warn("lock: 3D-ава не загрузилась — в quickshell нет модуля QtQuick3D?")
                        else if (status === Loader.Ready)
                            console.warn("lock: компонент 3D-авы создан")
                    }
                }

                // Снимок авы — с первого кадра лока, пока живая не готова.
                // Без sourceSize: так он берётся из кеша, куда его заранее
                // загрузил Lock.qml
                Image {
                    id: frameImg
                    anchors.fill: parent
                    source: root.ctx.avatarFrame
                    opacity: model3d.shown ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                ClippingRectangle {
                    anchors.centerIn: parent
                    width: 160; height: 160
                    radius: 80
                    color: Theme.surface0
                    visible: !model3d.shown && frameImg.status !== Image.Ready

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

                        CrossfadeImage {
                            anchors.fill: parent
                            source: Players.artUrl
                            sourceSize: Qt.size(128, 128)
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

                        // Длинное — колесом, как в попауте музыки
                        ScrollClip {
                            id: lockTitle
                            maxWidth: parent.width
                            fadeColor: Theme.crust

                            GradientText {
                                id: lockTitleText
                                pixelSize: 14
                                text: Players.title
                                onTextChanged: lockTitle.reset()
                                Behavior on text { TextFade { target: lockTitleText } }
                            }
                        }
                        ScrollClip {
                            id: lockArtist
                            visible: Players.artist !== ""
                            maxWidth: parent.width
                            fadeColor: Theme.crust

                            Text {
                                id: lockArtistText
                                text: Players.artist
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: Theme.subtext1
                                onTextChanged: lockArtist.reset()
                                Behavior on text { TextFade { target: lockArtistText } }
                            }
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

                    MorphText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font: "neofolia"
                        pixelSize: 96
                        color: Theme.gradStart
                        colorTo: Theme.gradEnd
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
                    text: "󰌌  " + (Compositor.langShort || "—")
                    fg: Theme.lavender

                    property real kick: 0
                    transform: Translate { y: -langBadge.kick }
                    scale: 1 + langBadge.kick / 40

                    SpringAnimation {
                        id: kickAnim
                        target: langBadge; property: "kick"; to: 0
                        spring: Motion.kickSpring; damping: Motion.kickDamping; epsilon: 0.05
                    }
                    Connections {
                        target: Compositor
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

                    PasswordField {
                        width: parent.width
                        height: parent.height
                        ctx: root.ctx
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
