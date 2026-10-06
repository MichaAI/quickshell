import Quickshell.Services.Notifications
import QtQuick
import ".."

// Карточка уведомления с анимацией ухода: уезжает вправо, тает,
// потом схлопывает своё место, и только после этого вызывается действие.
Item {
    id: root

    required property Notification notif
    property real gap: 0                 // отступ снизу — схлопывается вместе с карточкой
    property bool enter: false           // въехать справа при появлении
    // Схлопывать место после ухода. Последнему в стопке незачем: под ним
    // никто не подъедет, и схлопывание выглядело бы пустой паузой.
    property bool collapse: true
    readonly property bool hovered: card.hovered
    readonly property bool critical: card.critical
    readonly property bool leaving: outAnim.running

    property real slide: 0
    property real shrink: 1
    property var after: null
    property int delay: 0

    height: (card.implicitHeight + gap) * shrink

    // Уйти с анимацией и затем выполнить cb (если ещё актуально)
    function leave(cb, delayMs) {
        if (outAnim.running)
            return
        inAnim.stop()
        after = cb ?? null
        delay = delayMs ?? 0
        outAnim.start()
    }

    Component.onCompleted: if (enter) inAnim.start()

    NumberAnimation {
        id: inAnim
        target: root; property: "slide"; from: 1; to: 0
        duration: 250; easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: outAnim
        PauseAnimation { duration: root.delay }
        NumberAnimation {
            target: root; property: "slide"; to: 1
            duration: 200; easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root; property: "shrink"; to: 0
            duration: root.collapse ? 160 : 0; easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                if (root.after && root.notif)
                    root.after()
                root.after = null
            }
        }
    }

    NotifCard {
        id: card
        x: root.slide * (root.width + 16)
        width: root.width
        height: implicitHeight
        opacity: 1 - root.slide
        notif: root.notif
        // Крестик: убрать уведомление (всплывашка уйдёт сама по closed)
        onClosePressed: root.leave(() => root.notif.dismiss())
    }
}
