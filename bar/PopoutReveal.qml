import QtQuick
import "../config"
import "../components"

// Поэлементное появление содержимого попаута, как в MD3 Expressive.
// Один такой объект на элемент: как только нижний край попаута (edge)
// доезжает до верха элемента, тот начинает проявляться, а когда край
// проходит через его низ — дёргает элемент за собой вниз, и тот пружинит
// обратно. При закрытии гаснет, когда край уходит выше его середины.
Item {
    id: ctl

    required property Item modelData        // сам элемент
    property Item container                 // в чьих координатах edge
    property real edge: 0
    property bool open: false

    readonly property Item target: modelData
    property bool shown: false
    property bool tugged: false

    // Рывок: цель уходит вниз и возвращается, пружина тянет следом
    property real tugTarget: 0
    property real tugY: tugTarget
    Behavior on tugY { Spring { epsilon: 0.05 } }

    Translate {
        id: shift
        y: ctl.tugY
    }

    Component.onCompleted: {
        target.opacity = 0
        target.transform = Array.from(target.transform).concat([shift])
        check()
    }
    Component.onDestruction: {
        if (!target)
            return
        target.opacity = 1
        target.transform = Array.from(target.transform).filter(t => t !== shift)
    }

    onEdgeChanged: check()
    onOpenChanged: check()

    function check() {
        if (!target || !container)
            return
        // Позиции считаем на лету: столбцы раскладывают детей не сразу
        const top = target.mapToItem(container, 0, 0).y
        if (open && !shown && edge >= top + 1) {
            shown = true
            hideAnim.stop()
            showAnim.restart()
        }
        if (open && shown && !tugged && edge >= top + target.height) {
            tugged = true
            tugAnim.restart()
        }
        if (!open && shown && edge < top + target.height / 2) {
            shown = false
            tugged = false
            showAnim.stop()
            tugAnim.stop()
            tugTarget = 0
            hideAnim.restart()
        }
    }

    NumberAnimation {
        id: showAnim
        target: ctl.target; property: "opacity"; to: 1
        duration: Motion.contentFadeMs; easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: tugAnim
        PropertyAction { target: ctl; property: "tugTarget"; value: Motion.contentTug }
        PauseAnimation { duration: 110 }
        PropertyAction { target: ctl; property: "tugTarget"; value: 0 }
    }

    NumberAnimation {
        id: hideAnim
        target: ctl.target; property: "opacity"; to: 0
        duration: Motion.contentFadeMs / 2; easing.type: Easing.InCubic
    }
}
