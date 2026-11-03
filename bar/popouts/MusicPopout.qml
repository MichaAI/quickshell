pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../../config"
import "../../services"
import "../../components"
import "../../components/Shapes.js" as Shapes
import "../../components/Colors.js" as Colors

Item {
    id: root

    implicitWidth: 340
    implicitHeight: col.implicitHeight + 28

    readonly property var player: Players.active

    // Акценты попаута: из обложки (Settings.coverColors) или темы
    property var cover: null        // [начало, конец] из Colors.accents
    property color accentFrom: Settings.coverColors && cover ? Qt.rgba(cover[0].r, cover[0].g, cover[0].b, 1) : Theme.gradStart
    property color accentTo: Settings.coverColors && cover ? Qt.rgba(cover[1].r, cover[1].g, cover[1].b, 1) : Theme.gradEnd
    Behavior on accentFrom { ColorAnimation { duration: 400 } }
    Behavior on accentTo { ColorAnimation { duration: 400 } }

    // Свет обложки рисует бар: он ложится на весь шелл (попаут, бар, уголки)
    // между фоном и содержимым. Отсюда — только источник и где он лежит.
    readonly property Item glowSource: glowRounded
    // Свет идёт наплывом вместе с обложкой и на смене трека не гаснет
    readonly property bool glowOn: artFade.shown && glowSrc.shown
    readonly property point glowPos: Qt.point(col.x + coverRow.x + coverBox.x,
                                              col.y + coverRow.y + coverBox.y)

    // Метаданные — из Players: без провалов на смене трека
    readonly property string title: Players.title
    readonly property string artist: Players.artist
    // У синглов альбом обычно называется как трек — тогда не дублируем
    readonly property string album: Players.album === title ? "" : Players.album

    // Текущая обложка (из наплыва artFade): её читают пробы и свет
    readonly property Image art: artFade.image

    // Текст песни вместо эквалайзера — кнопкой, если его дал плеер или знает LRCLIB
    property bool showLyrics: false
    readonly property bool lyricsOn: showLyrics && Lyrics.available

    // Эквалайзер: cava живёт в сервисе и замерзает, пока попаут закрыт
    Component.onCompleted: Cava.viewers++
    Component.onDestruction: Cava.viewers--

    // Кнопка группы MD3 Expressive: тональная пилюля; нажатая шире и
    // квадратнее, соседи на это время ужимаются (ControlGroup.shift)
    component CtlBtn: Rectangle {
        id: btn
        property alias text: glyph.text
        property string svg: ""         // иконка от плеера (PlayerExt) вместо глифа
        property bool on: true
        property bool toggle: false     // переключатель: подсвечен, пока on
        property ControlGroup group
        property int idx: 0
        signal pressed()

        readonly property bool down: bma.pressed
        onDownChanged: group.press(idx, down)

        width: group.base + group.shift(idx)
        height: 36
        radius: group.pressedIdx === idx ? 10 : height / 2
        anchors.verticalCenter: parent.verticalCenter
        color: toggle && on ? Theme.alpha(group.accent, 0.22)
             : bma.containsMouse ? Theme.surface1 : Theme.surface0
        Behavior on width { Spring { epsilon: 0.05 } }
        Behavior on radius { Spring { epsilon: 0.05 } }
        Behavior on color { ColorAnimation { duration: 150 } }

        readonly property color fg: btn.toggle && btn.on ? btn.group.accent
                                  : btn.on ? Theme.text : Theme.overlay0

        Text {
            id: glyph
            visible: btn.svg === ""
            anchors.centerIn: parent
            font.family: Theme.font
            font.pixelSize: 16
            color: btn.fg
        }

        Image {
            visible: btn.svg !== ""
            anchors.centerIn: parent
            width: 18; height: 18
            sourceSize: Qt.size(36, 36)
            source: PlayerExt.icon(btn.svg, btn.fg)
        }

        MouseArea {
            id: bma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.pressed()
        }
    }

    // Ряд кнопок, который знает, какая нажата
    component ControlGroup: Row {
        property color accent: Theme.mauve
        property int base: 44
        property int pressedIdx: -1
        function press(i, down) {
            if (down)
                pressedIdx = i
            else if (pressedIdx === i)
                pressedIdx = -1
        }
        // Нажатая шире на 14, соседи уже на 7
        function shift(i) {
            if (pressedIdx < 0)
                return 0
            return i === pressedIdx ? 14 : Math.abs(i - pressedIdx) === 1 ? -7 : 0
        }
    }

    Column {
        id: col
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 14
        width: root.implicitWidth - 32
        spacing: 12

        // Обложка + инфо
        Row {
            id: coverRow
            width: parent.width
            spacing: 12

            // Нота лежит поверх, а не внутри ClippingRectangle: тот рисует
            // детей через слой, и текст в нём мылится
            Item {
                id: coverBox
                width: 64; height: 64

                // Источник света для бара (см. glowSource): скруглённая копия
                // обложки. Скругление до размытия — иначе квадратный свет
                // заливает срезанные углы и обложка выглядит квадратной.
                // Тоже наплывом: на смене трека свет перетекает в новый,
                // а не гаснет, пока грузится обложка
                CrossfadeImage {
                    id: glowSrc
                    anchors.fill: parent
                    source: Players.artUrl
                    sourceSize: Qt.size(48, 48)
                }
                // Текстурой для эффекта: слой невидимого элемента бар,
                // подключившись позже, видел пустым, пока обложка не сменится
                ShaderEffectSource {
                    id: glowTex
                    anchors.fill: parent
                    sourceItem: glowSrc
                    hideSource: true
                    visible: false
                }
                Rectangle {
                    id: glowMask
                    anchors.fill: parent
                    radius: 16
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    id: glowRounded
                    anchors.fill: parent
                    source: glowTex
                    maskEnabled: true
                    maskSource: glowMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                    visible: false
                    // Слой постоянный: включённый в тот же момент, когда бар
                    // создаёт свой эффект, он доходил до бара пустым
                    layer.enabled: true
                }
                ClippingRectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Theme.cardBg

                    // Яркость обложки там, где нота: центр видимого (после кропа)
                    // квадрата. Только считает, на экран не рисуется.
                    Canvas {
                        id: artProbe
                        width: 12; height: 12
                        visible: false

                        readonly property string src: root.art.status === Image.Ready ? root.art.source.toString() : ""
                        property string loaded: ""
                        property real luma: -1

                        // Пока новая обложка грузится, src пуст — держим
                        // прежнюю яркость, сбрасываем, только если обложки нет
                        onSrcChanged: {
                            if (src === "" && Players.artUrl !== "") return
                            luma = -1
                            if (loaded !== "")
                                unloadImage(loaded)
                            loaded = src
                            if (src !== "") {
                                loadImage(src)
                                if (isImageLoaded(src))
                                    requestPaint()
                            }
                        }
                        onImageLoaded: requestPaint()

                        onPaint: {
                            if (src === "" || !isImageLoaded(src))
                                return
                            const ctx = getContext("2d")
                            const w = root.art.implicitWidth, h = root.art.implicitHeight
                            const c = Math.min(w, h) * 0.4
                            ctx.clearRect(0, 0, width, height)
                            ctx.drawImage(src, (w - c) / 2, (h - c) / 2, c, c, 0, 0, width, height)
                            const d = ctx.getImageData(0, 0, width, height).data
                            let sum = 0
                            for (let i = 0; i < d.length; i += 4)
                                sum += 0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]
                            luma = sum / (d.length / 4) / 255
                        }
                    }

                    // Оттенки всей обложки для акцентов (Colors.accents)
                    Canvas {
                        id: paletteProbe
                        width: 48; height: 48
                        visible: false

                        readonly property string src: Settings.coverColors && root.art.status === Image.Ready ? root.art.source.toString() : ""
                        property string loaded: ""

                        // Как у artProbe: цвета не уходят в тему на время
                        // загрузки, а сразу перетекают в новые
                        onSrcChanged: {
                            if (src === "" && Players.artUrl !== "" && Settings.coverColors) return
                            root.cover = null
                            if (loaded !== "")
                                unloadImage(loaded)
                            loaded = src
                            if (src !== "") {
                                loadImage(src)
                                if (isImageLoaded(src))
                                    requestPaint()
                            }
                        }
                        onImageLoaded: requestPaint()

                        onPaint: {
                            if (src === "" || !isImageLoaded(src))
                                return
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.drawImage(src, 0, 0, width, height)
                            root.cover = Colors.accents(ctx.getImageData(0, 0, width, height).data, 0.77, 0.13)
                        }
                    }

                    CrossfadeImage {
                        id: artFade
                        anchors.fill: parent
                        source: Players.artUrl
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰝚"
                    font.family: Theme.font
                    font.pixelSize: 24
                    color: artProbe.luma < 0 ? Theme.surface2
                         : artProbe.luma > 0.5 ? Theme.crust
                         : Theme.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }

            // Инфо, справа — кнопка текста песни: в ряду управления она
            // сбивала его с центра. Место под неё освобождается пружиной
            Item {
                width: parent.width - 76
                height: 64

                Column {
                    width: parent.width - (Lyrics.available ? lyricsBtn.width + 8 : 0)
                    Behavior on width { Spring { epsilon: 0.5 } }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    // Клик копирует, колесо прокручивает длинное
                    ScrollClip {
                        id: titleClip
                        maxWidth: parent.width
                        fadeColor: Theme.popoutBg
                        clickable: !!root.player
                        onClicked: { Tools.copy(root.title); titleClip.flash() }

                        GradientText {
                            id: titleText
                            pixelSize: 15
                            from: root.accentFrom
                            to: root.accentTo
                            text: root.title
                            onTextChanged: titleClip.reset()
                            Behavior on text { TextFade { target: titleText } }
                        }
                    }
                    ScrollClip {
                        id: artistClip
                        visible: root.artist !== ""
                        maxWidth: parent.width
                        fadeColor: Theme.popoutBg
                        clickable: true
                        onClicked: { Tools.copy(root.artist); artistClip.flash() }

                        Text {
                            id: artistText
                            text: root.artist
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: Theme.subtext1
                            onTextChanged: artistClip.reset()
                            Behavior on text { TextFade { target: artistText } }
                        }
                    }
                    ScrollClip {
                        id: albumClip
                        visible: root.album !== ""
                        maxWidth: parent.width
                        fadeColor: Theme.popoutBg
                        clickable: true
                        onClicked: { Tools.copy(root.album); albumClip.flash() }

                        Text {
                            id: albumText
                            text: root.album
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.overlay1
                            onTextChanged: albumClip.reset()
                            Behavior on text { TextFade { target: albumText } }
                        }
                    }
                }

                Rectangle {
                    id: lyricsBtn
                    readonly property bool shown: Lyrics.available
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: 30; height: 30
                    radius: 15
                    color: root.showLyrics ? Theme.alpha(root.accentTo, 0.22)
                         : lma.containsMouse ? Theme.surface1 : Theme.surface0
                    Behavior on color { ColorAnimation { duration: 150 } }
                    opacity: shown ? 1 : 0
                    scale: shown ? (lma.pressed ? 0.9 : 1) : 0.6
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { Spring { epsilon: 0.002 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰍡"
                        font.family: Theme.font
                        font.pixelSize: 14
                        color: root.showLyrics ? root.accentTo : Theme.text
                    }
                    MouseArea {
                        id: lma
                        anchors.fill: parent
                        enabled: lyricsBtn.shown
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showLyrics = !root.showLyrics
                    }
                }
            }
        }

        // Текст песни над эквалайзером: место под текст раздвигается пружиной
        Item {
            id: midArea
            width: parent.width
            height: root.lyricsOn ? 140 + 8 + 42 : 42
            Behavior on height { Spring { epsilon: 0.5 } }
            clip: true
            // Для PopoutReveal: проявлять целиком. Иначе он сам выставит
            // opacity панели текста и её строкам и перебьёт их привязки —
            // панель не прячется, строки не подсвечиваются
            readonly property bool revealWhole: true

            Row {
                id: eqRow
                width: parent.width
                height: 42
                anchors.bottom: parent.bottom
                spacing: 3

                readonly property int n: Math.max(1, Cava.bars.length)
                readonly property real barW: (width - spacing * (n - 1)) / n

                Repeater {
                    model: Cava.bars.length

                    Rectangle {
                        required property int index
                        width: eqRow.barW
                        height: Math.max(3, (Cava.bars[index] ?? 0) / 100 * eqRow.height)
                        anchors.bottom: parent.bottom
                        radius: width / 2.5
                        color: Theme.mix(root.accentFrom, root.accentTo,
                                         eqRow.n > 1 ? index / (eqRow.n - 1) : 0)
                        opacity: 0.4 + 0.6 * ((Cava.bars[index] ?? 0) / 100)

                        Behavior on height {
                            NumberAnimation { duration: 60 }
                        }
                    }
                }
            }

            // Текст песни: звучащая строка — посередине и в цвет обложки,
            // соседние тише. Клик по строке перематывает к ней
            Item {
                id: lyr
                width: parent.width
                height: 140
                opacity: root.lyricsOn ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // Позиция MPRIS тикает раз в секунду — между тиками досчитываем сами
                property real base: root.player?.position ?? 0
                property real stamp: Date.now()
                property real pos: base
                Connections {
                    target: root.player
                    function onPositionChanged() {
                        lyr.base = root.player.position
                        lyr.stamp = Date.now()
                    }
                }
                FrameAnimation {
                    running: lyr.visible && Lyrics.synced
                    onTriggered: lyr.pos = lyr.base + (root.player?.isPlaying ? (Date.now() - lyr.stamp) / 1000 : 0)
                }
                readonly property int cur: Lyrics.lineAt(pos + 0.15)

                ListView {
                    id: lyrList
                    anchors.fill: parent
                    clip: true
                    spacing: 6
                    model: Lyrics.lines
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: Math.max(0, lyr.cur)
                    highlightRangeMode: Lyrics.synced ? ListView.ApplyRange : ListView.NoHighlightRange
                    preferredHighlightBegin: height / 2 - 12
                    preferredHighlightEnd: height / 2 + 12
                    highlightMoveDuration: 450
                    highlightMoveVelocity: -1

                    // Для строк: снаружи делегата видно только сам список
                    readonly property int cur: lyr.cur
                    readonly property color accent: Theme.mix(root.accentFrom, root.accentTo, 0.5)
                    readonly property bool canSeek: Lyrics.synced && (root.player?.canSeek ?? false)
                    function seek(t) { root.player.position = t }

                    delegate: Text {
                        id: line
                        required property var modelData
                        required property int index
                        readonly property var view: ListView.view
                        readonly property bool current: Lyrics.synced && line.index === view.cur
                        width: view.width
                        // Справа — место под кнопку копирования
                        leftPadding: 30
                        rightPadding: 30
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: line.modelData.text || "♪"
                        font.family: Theme.font
                        // Без жирного: он перекладывал строку и обрезал её край
                        font.pixelSize: 13
                        color: line.current ? view.accent : Theme.subtext0
                        opacity: !Lyrics.synced ? 0.9
                               : line.current ? 1 : Math.max(0.3, 0.8 - 0.15 * Math.abs(line.index - view.cur))
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        Behavior on color { ColorAnimation { duration: 250 } }

                        HoverHandler {
                            enabled: line.view.canSeek
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            enabled: line.view.canSeek
                            onTapped: line.view.seek(line.modelData.t)
                        }
                    }
                }

                // Копировать весь текст
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    width: 26; height: 26; radius: 13
                    color: copyMa.containsMouse ? Theme.surface1 : Theme.surface0
                    opacity: 0.9
                    Text {
                        id: copyGlyph
                        anchors.centerIn: parent
                        text: "󰆏"
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.text
                    }
                    MouseArea {
                        id: copyMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Tools.copy(Lyrics.plain)
                            copyGlyph.text = "󰄬"
                            copied.restart()
                        }
                    }
                    Timer {
                        id: copied
                        interval: 1200
                        onTriggered: copyGlyph.text = "󰆏"
                    }
                }
            }
        }

        // Прогресс
        Column {
            width: parent.width
            spacing: 2

            // Позиция каждый кадр, а не раз в секунду (тикает Players): иначе
            // ползунок шагает, на коротких треках заметно. Quickshell сам
            // досчитывает position по часам — тут только будим привязки
            FrameAnimation {
                running: root.visible && (root.player?.isPlaying ?? false)
                onTriggered: root.player.positionChanged()
            }

            StyledSlider {
                width: parent.width
                wavy: true
                // Перемотка по MPRIS — не чаще восьми раз в секунду
                sendEvery: 125
                // Своя позиция — в пределах полутора секунд трека
                holdTolerance: (root.player?.length ?? 0) > 0 ? 1.5 / root.player.length : 0.01
                colorFrom: root.accentFrom
                colorTo: root.accentTo
                moving: root.player?.isPlaying ?? false
                valueText: v => Players.fmt(v * (root.player?.length ?? 0))
                enabled: (root.player?.canSeek ?? false) && (root.player?.length ?? 0) > 0
                value: root.player && root.player.length > 0
                    ? root.player.position / root.player.length : 0
                onMoved: v => {
                    if (root.player && root.player.canSeek && root.player.length > 0)
                        root.player.position = v * root.player.length
                }
            }

            Item {
                width: parent.width
                height: 14

                Text {
                    anchors.left: parent.left
                    text: Players.fmt(root.player?.position ?? 0)
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.overlay1
                }
                Text {
                    anchors.right: parent.right
                    text: Players.fmt(root.player?.length ?? 0)
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.overlay1
                }
            }
        }

        // Управление
        Item {
            width: parent.width
            height: 44

            ControlGroup {
                id: controls
                anchors.centerIn: parent
                spacing: 6
                accent: root.accentTo
                // С кнопками плеера по краям ряд не влезает — все уже
                base: PlayerExt.leftIcon !== "" || PlayerExt.rightIcon !== "" ? 36 : 44

                // Кнопки расширения плеера (PlayerExt): иконка и действие — его
                CtlBtn {
                    group: controls; idx: 0
                    svg: PlayerExt.leftIcon
                    visible: svg !== ""
                    onPressed: PlayerExt.left()
                }

                CtlBtn {
                    group: controls; idx: 1
                    toggle: true
                    text: "󰒝"
                    on: root.player?.shuffle ?? false
                    visible: root.player?.shuffleSupported ?? false
                    onPressed: root.player.shuffle = !root.player.shuffle
                }

                CtlBtn {
                    group: controls; idx: 2
                    text: "󰒮"
                    on: root.player?.canGoPrevious ?? false
                    onPressed: if (root.player?.canGoPrevious) root.player.previous()
                }

                // Круг на паузе, печенька при игре — и медленно крутится,
                // как пластинка
                MaterialShape {
                    id: playBtn
                    width: 42; height: 42
                    anchors.verticalCenter: parent.verticalCenter
                    from: Shapes.circle
                    to: Shapes.cookie9
                    colorFrom: root.accentFrom
                    colorTo: root.accentTo
                    morph: Players.playing ? 1 : 0
                    Behavior on morph { Spring { epsilon: 0.002 } }
                    // В группе: нажатая раздувается, соседи ужимаются
                    scale: pma.pressed ? 1.12 : pma.containsMouse ? 1.06 : 1
                    Behavior on scale { Spring { epsilon: 0.002 } }

                    FrameAnimation {
                        running: playBtn.morph > 0.01 && playBtn.visible
                        onTriggered: playBtn.turn = (playBtn.turn + frameTime / 12) % 1
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Players.playing ? "󰏤" : "󰐊"
                        font.family: Theme.font
                        font.pixelSize: 20
                        color: Theme.crust
                    }
                    MouseArea {
                        id: pma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.player?.togglePlaying()
                        onPressedChanged: controls.press(3, pressed)
                    }
                }

                CtlBtn {
                    group: controls; idx: 4
                    text: "󰒭"
                    on: root.player?.canGoNext ?? false
                    onPressed: if (root.player?.canGoNext) root.player.next()
                }

                CtlBtn {
                    group: controls; idx: 5
                    toggle: true
                    text: root.player?.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                    on: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                    visible: root.player?.loopSupported ?? false
                    onPressed: {
                        const s = root.player.loopState
                        root.player.loopState =
                            s === MprisLoopState.None ? MprisLoopState.Playlist
                          : s === MprisLoopState.Playlist ? MprisLoopState.Track
                          : MprisLoopState.None
                    }
                }

                CtlBtn {
                    group: controls; idx: 6
                    svg: PlayerExt.rightIcon
                    visible: svg !== ""
                    onPressed: PlayerExt.right()
                }
            }
        }

        // Выбор плеера
        Flow {
            visible: Players.list.length > 1
            width: parent.width
            spacing: 6

            Repeater {
                model: Players.list

                Rectangle {
                    required property var modelData
                    width: pt.implicitWidth + 16
                    height: 22
                    radius: 11
                    color: modelData === root.player ? Theme.surface0 : Theme.cardBg

                    Text {
                        id: pt
                        anchors.centerIn: parent
                        text: parent.modelData.identity
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: parent.modelData === root.player ? Theme.mauve : Theme.overlay1
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Players.select(parent.modelData)
                    }
                }
            }
        }
    }
}
