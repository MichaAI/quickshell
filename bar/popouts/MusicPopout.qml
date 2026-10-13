import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../.."
import "../../services"
import "../../components"

Item {
    id: root

    implicitWidth: 340
    implicitHeight: col.implicitHeight + 28

    readonly property var player: Players.active

    readonly property string title: player?.trackTitle || "Ничего не играет"
    readonly property string artist: player?.trackArtist ?? ""
    // У синглов альбом обычно называется как трек — тогда не дублируем
    readonly property string album: {
        const a = player?.trackAlbum ?? ""
        return a === title ? "" : a
    }

    // ===== Эквалайзер (cava) =====
    property var eqBars: []

    Process {
        id: cavaProc
        command: ["cava", "-p", Qt.resolvedUrl("../../assets/cava.conf").toString().replace("file://", "")]
        running: true

        stdout: SplitParser {
            onRead: line => {
                const vals = line.split(";").filter(s => s !== "").map(Number)
                if (vals.length > 0)
                    root.eqBars = vals
            }
        }
    }

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
            width: parent.width
            spacing: 12

            // Нота лежит поверх, а не внутри ClippingRectangle: тот рисует
            // детей через слой, и текст в нём мылится
            Item {
                width: 64; height: 64

                // Свечение: размытая копия обложки под ней, в её же цветах.
                // Копия скругляется до размытия — иначе квадратная подложка
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
                    layer.enabled: true
                }
                // Свет и зерно поверх него. Размытие небольшое: обложка в 14px
                // от верха попаута, больший хвост обрезался бы его краем
                Item {
                    id: glow
                    anchors.fill: parent
                    anchors.margins: -24
                    opacity: art.visible && glowSrc.status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }

                    Item {
                        id: glowLight
                        anchors.fill: parent
                        layer.enabled: true

                        MultiEffect {
                            x: 24; y: 24; width: 64; height: 64
                            source: glowRounded
                            blurEnabled: true
                            blur: 1
                            blurMax: 16
                            saturation: 0.4
                            brightness: 0.1
                            scale: 1.04
                        }
                    }

                    // Дизеринг: тайловый шум по альфе света, против полос в градиенте
                    Image {
                        id: glowNoise
                        anchors.fill: parent
                        source: Qt.resolvedUrl("../../assets/noise.png")
                        fillMode: Image.Tile
                        smooth: false
                        visible: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: glowNoise
                        maskEnabled: true
                        maskSource: glowLight
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                        opacity: 0.05
                    }
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

            readonly property int n: Math.max(1, root.eqBars.length)
            readonly property real barW: (width - spacing * (n - 1)) / n

            Repeater {
                model: root.eqBars.length

                Rectangle {
                    required property int index
                    width: eqRow.barW
                    height: Math.max(3, (root.eqBars[index] ?? 0) / 100 * eqRow.height)
                    anchors.bottom: parent.bottom
                    radius: width / 2.5
                    color: Theme.mix(Theme.gradStart, Theme.gradEnd,
                                     eqRow.n > 1 ? index / (eqRow.n - 1) : 0)
                    opacity: 0.4 + 0.6 * ((root.eqBars[index] ?? 0) / 100)

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

                Rectangle {
                    width: 42; height: 42
                    radius: 21
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.gradStart }
                        GradientStop { position: 1; color: Theme.gradEnd }
                    }
                    scale: pma.containsMouse ? 1.08 : 1
                    Behavior on scale { NumberAnimation { duration: 100 } }

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
