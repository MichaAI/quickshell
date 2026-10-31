pragma ComponentBehavior: Bound

import QtQuick

// Картинка со сменой наплывом: новая грузится во вторую Image и
// проявляется поверх старой, а старая до конца остаётся непрозрачной —
// без провала посередине. Картинки по очереди: старую никуда не
// перекладываем, так что она не перезагружается. Пустой или битый
// source — старая гаснет.
// image — текущая (для status, source и размеров); shown — видна хоть
// какая-то картинка (новая или ещё не погасшая старая)
Item {
    id: root

    property url source
    property int fillMode: Image.PreserveAspectCrop
    property size sourceSize
    property int duration: 300

    property bool flip: false
    readonly property Image image: flip ? b : a
    readonly property Image other: flip ? a : b
    readonly property bool shown: a.status === Image.Ready && a.opacity > 0
        || b.status === Image.Ready && b.opacity > 0

    component Img: Image {
        anchors.fill: parent
        fillMode: root.fillMode
        sourceSize: root.sourceSize
        visible: opacity > 0
        // Текущая всегда сверху
        z: this === root.image ? 1 : 0
        onStatusChanged: {
            if (this !== root.image) return
            if (status === Image.Ready) root.reveal()
            else if (status === Image.Error) root.hide()
        }
    }

    Img { id: a }
    Img { id: b; opacity: 0 }

    function reveal() {
        hideAnim.stop()
        const cur = image
        fade.stop()
        fade.target = cur
        fade.from = cur.opacity
        fade.start()
    }

    function hide() {
        fade.stop()
        hideAnim.restart()
    }

    function dropOther() {
        other.opacity = 0
        other.source = ""
    }

    onSourceChanged: {
        if (root.source.toString() === "") {
            hide()
            return
        }
        hideAnim.stop()
        const cur = image
        if (cur.status === Image.Ready && cur.opacity > 0) {
            // Видна текущая: она уходит под низ, новая грузится поверх с нуля
            fade.stop()
            dropOther()
            cur.opacity = 1
            const next = other
            next.opacity = 0
            flip = !flip
            next.source = root.source
        } else {
            // Текущая не видна (грузится или погашена) — грузим прямо в неё;
            // старая под ней, если есть, остаётся до наплыва
            if (cur.opacity > 0 && cur.status !== Image.Ready) cur.opacity = 0
            cur.source = root.source
        }
        if (image.status === Image.Ready) reveal()
    }

    NumberAnimation {
        id: fade
        property: "opacity"
        to: 1
        duration: root.duration
        easing.type: Easing.OutCubic
        // Новая проявилась — старая под ней больше не нужна
        onFinished: root.dropOther()
    }

    // Первая показывается сразу, без наплыва (как только загрузится).
    // Не биндингом: a потом сама уходит под низ и должна держать своё
    Component.onCompleted: a.source = root.source

    ParallelAnimation {
        id: hideAnim
        NumberAnimation { target: a; property: "opacity"; to: 0; duration: root.duration; easing.type: Easing.InCubic }
        NumberAnimation { target: b; property: "opacity"; to: 0; duration: root.duration; easing.type: Easing.InCubic }
    }
}
