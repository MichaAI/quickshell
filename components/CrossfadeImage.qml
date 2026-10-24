import QtQuick

// Картинка со сменой наплывом: новая проявляется поверх старой, когда
// загрузится; пустой или битый source — старая просто гаснет.
// image — текущая (для status, source и размеров)
Item {
    id: root

    property url source
    property int fillMode: Image.PreserveAspectCrop
    property size sourceSize
    property int duration: 300
    readonly property Image image: front

    Image {
        id: back
        anchors.fill: parent
        fillMode: root.fillMode
        sourceSize: root.sourceSize
        visible: opacity > 0
    }

    Image {
        id: front
        anchors.fill: parent
        fillMode: root.fillMode
        sourceSize: root.sourceSize
        onStatusChanged: {
            if (status === Image.Ready)
                fadeIn.restart()
            else if (status === Image.Error)
                fadeOut.restart()
        }
    }

    onSourceChanged: {
        fadeIn.stop()
        fadeOut.stop()
        // Старая уходит назад и гаснет, когда новая проявится. Если новая
        // ещё сама проявлялась — назад уходит с той прозрачностью, что есть
        const had = front.status === Image.Ready
        back.source = had ? front.source : ""
        back.opacity = had ? Math.max(front.opacity, back.opacity) : back.opacity
        front.opacity = 0
        front.source = root.source
        if (root.source.toString() === "")
            fadeOut.restart()
    }

    Component.onCompleted: {
        front.source = root.source
        front.opacity = 1
    }

    ParallelAnimation {
        id: fadeIn
        NumberAnimation { target: front; property: "opacity"; to: 1; duration: root.duration; easing.type: Easing.OutCubic }
        NumberAnimation { target: back; property: "opacity"; to: 0; duration: root.duration; easing.type: Easing.InCubic }
    }

    NumberAnimation {
        id: fadeOut
        target: back
        property: "opacity"
        to: 0
        duration: root.duration
        easing.type: Easing.InCubic
    }
}
