import QtQuick
import Quickshell.Services.Pipewire
import "../../config"
import "../../services"
import "../../components"

Item {
    id: root

    implicitWidth: 340
    implicitHeight: col.implicitHeight + 28

    // Отслеживаем потоки приложений, пока попаут открыт
    PwObjectTracker { objects: Audio.streams }

    component VolRow: Item {
        property alias icon: ico.text
        property alias iconColor: ico.color
        property string label: ""
        property real value: 0
        property bool muted: false
        signal moved(real value)
        signal mutePressed()

        width: parent.width
        height: Math.max(44, body.implicitHeight)

        Text {
            id: ico
            width: 24
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font
            font.pixelSize: 17
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.parent.mutePressed()
            }
        }

        Column {
            id: body
            anchors.left: ico.right
            anchors.leftMargin: 10
            anchors.right: perc.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: parent.parent.label
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.overlay1
                visible: text !== ""
            }
            StyledSlider {
                width: parent.width
                value: parent.parent.value
                onMoved: v => parent.parent.moved(v)
            }
        }

        Text {
            id: perc
            width: 34
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(parent.value * 100) + ""
            horizontalAlignment: Text.AlignRight
            font.family: Theme.font
            font.pixelSize: 12
            color: parent.muted ? Theme.overlay0 : Theme.text
        }
    }

    Column {
        id: col
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 14
        width: root.implicitWidth - 32
        spacing: 8

        GradientText {
            text: "Громкость"
            pixelSize: 17
            display: true
        }

        Rectangle {
            width: parent.width
            implicitHeight: outCol.implicitHeight + 20
            radius: 12
            color: Theme.cardBg

            Column {
                id: outCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 0

                VolRow {
                    icon: Audio.icon
                    iconColor: Audio.muted ? Theme.red : Theme.teal
                    label: Audio.sinkName
                    value: Audio.volume
                    muted: Audio.muted
                    onMoved: v => Audio.setVolume(v)
                    onMutePressed: Audio.toggleMute()
                }

                VolRow {
                    icon: Audio.micMuted ? "󰍭" : "󰍬"
                    iconColor: Audio.micMuted ? Theme.red : Theme.sky
                    label: Audio.sourceName
                    value: Audio.micVolume
                    muted: Audio.micMuted
                    onMoved: v => Audio.setMicVolume(v)
                    onMutePressed: Audio.toggleMicMute()
                }
            }
        }

        Text {
            text: "Приложения"
            font.family: Theme.font
            font.pixelSize: 12
            color: Theme.overlay1
            visible: Audio.streams.length > 0
        }

        Rectangle {
            width: parent.width
            implicitHeight: appCol.implicitHeight + 20
            radius: 12
            color: Theme.cardBg
            visible: Audio.streams.length > 0

            Column {
                id: appCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 0

                Repeater {
                    model: Audio.streams

                    VolRow {
                        required property var modelData
                        icon: modelData.audio?.muted ? "󰝟" : "󰕾"
                        iconColor: modelData.audio?.muted ? Theme.red : Theme.lavender
                        label: Audio.streamName(modelData)
                        value: modelData.audio?.volume ?? 0
                        muted: modelData.audio?.muted ?? false
                        onMoved: v => { if (modelData.audio) modelData.audio.volume = v }
                        onMutePressed: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                    }
                }
            }
        }
    }
}
