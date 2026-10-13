import QtQuick
import Quickshell
import Quickshell.Widgets
import ".."
import "../services"
import "../components"

// Содержимое экрана блокировки на одном мониторе. Состояние — в ctx (Lock).
Item {
    id: root

    required property var ctx

    component Btn: Text {
        id: btn
        signal pressed()
        width: 30; height: 30
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.font
        font.pixelSize: 18
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

    // Фон: тот же crust, что у шелла, с лёгким зерном
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

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        spacing: 22

        // ===== Часы =====
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            GradientText {
                anchors.horizontalCenter: parent.horizontalCenter
                display: true
                pixelSize: 120
                outlineWidth: 5
                outlineColor: Theme.crust
                text: Qt.formatDateTime(Time.now, "HH:mm")
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    const d = Time.dateLong
                    return d.charAt(0).toUpperCase() + d.slice(1)
                }
                font.family: Theme.font
                font.pixelSize: 15
                color: Theme.subtext0
            }
        }

        // ===== Аватар =====
        // 3D-модель ~/avatar.*, если она есть и в quickshell доступен
        // QtQuick3D; иначе ~/.face; иначе ничего
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: model3d.shown ? 220 : face.visible ? 96 : 0
            height: width
            visible: width > 0

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
                id: face
                anchors.centerIn: parent
                width: 96; height: 96
                radius: 48
                color: "transparent"
                visible: !model3d.shown && faceImg.status === Image.Ready

                Image {
                    id: faceImg
                    anchors.fill: parent
                    source: "file://" + root.ctx.home + "/.face"
                    sourceSize: Qt.size(192, 192)
                    fillMode: Image.PreserveAspectCrop
                }
            }
        }

        // ===== Раскладка и Caps Lock над полем =====
        Row {
            id: badges
            anchors.horizontalCenter: parent.horizontalCenter
            height: 26
            spacing: capsBadge.width > 1 ? 8 : 0

            Rectangle {
                id: langBadge
                width: langText.implicitWidth + 20
                height: 26
                radius: 13
                color: Theme.surface0

                // Смена раскладки — пинок: значок подпрыгивает и пружинит обратно
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

                Text {
                    id: langText
                    anchors.centerIn: parent
                    text: "󰌌  " + (Niri.langShort || "—")
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.bold: true
                    color: Theme.lavender
                }
            }

            Item {
                id: capsBadge
                width: root.ctx.caps ? capsRect.width : 0
                height: 26
                Behavior on width { Spring {} }

                Rectangle {
                    id: capsRect
                    anchors.left: parent.left
                    width: capsText.implicitWidth + 20
                    height: 26
                    radius: 13
                    color: Theme.alpha(Theme.peach, 0.18)
                    scale: root.ctx.caps ? 1 : 0
                    Behavior on scale { Spring { epsilon: 0.002 } }

                    Text {
                        id: capsText
                        anchors.centerIn: parent
                        text: "󰘲  CAPS"
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.bold: true
                        color: Theme.peach
                    }
                }
            }
        }

        // ===== Поле пароля =====
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300
            height: 46

            Rectangle {
                id: field
                width: parent.width
                height: parent.height
                radius: 23
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
                        model: Math.min(root.ctx.text.length, 22)

                        Rectangle {
                            id: dot
                            required property int index
                            width: 9; height: 9
                            radius: 4.5
                            color: Theme.mix(Theme.gradStart, Theme.gradEnd, index / 21)
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
    }

    // ===== Музыка =====
    Rectangle {
        id: music
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48
        visible: Players.active !== null
        width: Math.min(420, musicRow.implicitWidth + 24)
        height: 68
        radius: 20
        color: Theme.crust
        border.width: 1
        border.color: Theme.surface0

        Row {
            id: musicRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            spacing: 12

            ClippingRectangle {
                width: 48; height: 48
                radius: 12
                color: Theme.surface0
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    anchors.fill: parent
                    source: Players.active?.trackArtUrl ?? ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectCrop
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 220)
                spacing: 2

                GradientText {
                    pixelSize: 13
                    maxChars: 26
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
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

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
