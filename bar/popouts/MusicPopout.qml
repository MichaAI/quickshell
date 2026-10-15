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
    readonly property bool glowOn: art.visible && glowSrc.status === Image.Ready
    readonly property point glowPos: Qt.point(col.x + coverRow.x + coverBox.x,
                                              col.y + coverRow.y + coverBox.y)

    readonly property string title: player?.trackTitle || "Ничего не играет"
    readonly property string artist: player?.trackArtist ?? ""
    // У синглов альбом обычно называется как трек — тогда не дублируем
    readonly property string album: {
        const a = player?.trackAlbum ?? ""
        return a === title ? "" : a
    }

    // Эквалайзер: cava живёт в сервисе и замерзает, пока попаут закрыт
    Component.onCompleted: Cava.viewers++
    Component.onDestruction: Cava.viewers--

    component CtlBtn: Text {
        property bool on: true
        signal pressed()
        font.family: Theme.font
        font.pixelSize: 16
        color: bma.containsMouse ? Theme.text : (on ? Theme.subtext1 : Theme.overlay0)
        anchors.verticalCenter: parent.verticalCenter

        MouseArea {
            id: bma
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.pressed()
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
                // заливает срезанные углы и обложка выглядит квадратной
                Image {
                    id: glowSrc
                    anchors.fill: parent
                    source: art.source
                    sourceSize: Qt.size(48, 48)
                    fillMode: Image.PreserveAspectCrop
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
                    source: glowSrc
                    maskEnabled: true
                    maskSource: glowMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                    visible: false
                    // Без обложки источника нет — не гоняем эффект впустую
                    layer.enabled: glowSrc.status === Image.Ready
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

                        readonly property string src: art.status === Image.Ready ? art.source.toString() : ""
                        property string loaded: ""
                        property real luma: -1

                        onSrcChanged: {
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
                            const w = art.implicitWidth, h = art.implicitHeight
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
                        width: 24; height: 24
                        visible: false

                        readonly property string src: Settings.coverColors && art.status === Image.Ready ? art.source.toString() : ""
                        property string loaded: ""

                        onSrcChanged: {
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

                    Image {
                        id: art
                        anchors.fill: parent
                        source: root.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰝚"
                    font.family: Theme.font
                    font.pixelSize: 24
                    color: !art.visible || artProbe.luma < 0 ? Theme.surface2
                         : artProbe.luma > 0.5 ? Theme.crust
                         : Theme.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }

            Column {
                width: parent.width - 76
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
                        pixelSize: 15
                        from: root.accentFrom
                        to: root.accentTo
                        text: root.title
                        onTextChanged: titleClip.reset()
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
                        text: root.artist
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.subtext1
                        onTextChanged: artistClip.reset()
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
                        text: root.album
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.overlay1
                        onTextChanged: albumClip.reset()
                    }
                }
            }
        }

        // Эквалайзер
        Row {
            id: eqRow
            width: parent.width
            height: 42
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

        // Прогресс
        Column {
            width: parent.width
            spacing: 2

            StyledSlider {
                width: parent.width
                wavy: true
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

            Row {
                anchors.centerIn: parent
                spacing: 18

                CtlBtn {
                    text: "󰒝"
                    on: root.player?.shuffle ?? false
                    visible: root.player?.shuffleSupported ?? false
                    onPressed: root.player.shuffle = !root.player.shuffle
                }

                CtlBtn {
                    text: "󰒮"
                    on: root.player?.canGoPrevious ?? false
                    onPressed: if (root.player?.canGoPrevious) root.player.previous()
                }

                // Круг на паузе, печенька при игре — и медленно крутится,
                // как пластинка
                MorphShape {
                    id: playBtn
                    width: 42; height: 42
                    anchors.verticalCenter: parent.verticalCenter
                    from: Shapes.circle
                    to: Shapes.cookie9
                    colorFrom: root.accentFrom
                    colorTo: root.accentTo
                    morph: Players.playing ? 1 : 0
                    Behavior on morph { Spring { epsilon: 0.002 } }
                    scale: pma.pressed ? 0.9 : pma.containsMouse ? 1.08 : 1
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
                    }
                }

                CtlBtn {
                    text: "󰒭"
                    on: root.player?.canGoNext ?? false
                    onPressed: if (root.player?.canGoNext) root.player.next()
                }

                CtlBtn {
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
                        onClicked: Players.selected = parent.modelData
                    }
                }
            }
        }
    }
}
