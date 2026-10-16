import Quickshell.Services.Notifications
import QtQuick
import "../config"
import "../services"

// Карточка уведомления с анимацией ухода: уезжает вбок, тает,
// потом схлопывает своё место, и только после этого вызывается действие.
// Смахивается двумя пальцами по тачпаду: едет за пальцами, отпущенная
// дальше трети ширины — улетает и закрывает уведомление, иначе пружинит назад.
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
    property real drag: 0                // смещение пальцами, px
    property bool swiping: false         // пальцы сейчас тянут карточку
    property int dir: 1                  // куда уезжать: 1 — вправо, -1 — влево
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

    // ===== Свайп двумя пальцами =====
    // Слушает только горизонтальную составляющую (по умолчанию WheelHandler
    // берёт лишь события с вертикальной и чисто вбок не срабатывал). Пока
    // карточку не тянут, события идут дальше — список листается как обычно;
    // отказаться от события из onWheel нельзя, поэтому через blocking.
    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.TouchPad
        orientation: Qt.Horizontal
        blocking: root.swiping
        onWheel: event => {
            const dx = event.pixelDelta.x, dy = event.pixelDelta.y
            // Вертикальное — список листать; инерция после отпускания — мимо
            if (root.leaving || event.phase === Qt.ScrollMomentum
                    || (!root.swiping && Math.abs(dx) <= Math.abs(dy)))
                return
            root.swiping = true
            snapBack.stop()
            root.drag += Settings.notifSwipeInvert ? -dx : dx
            if (event.phase === Qt.ScrollEnd)
                root.release()
            else
                releaseTimer.restart()
        }
    }
    // Не все тачпады шлют конец жеста — тогда конец по паузе
    Timer {
        id: releaseTimer
        interval: 150
        onTriggered: root.release()
    }
    function release() {
        releaseTimer.stop()
        swiping = false
        if (Math.abs(drag) > width / 3) {
            dir = drag > 0 ? 1 : -1
            leave(() => root.notif.dismiss())
        } else {
            snapBack.start()
        }
    }
    Spring {
        id: snapBack
        target: root; property: "drag"; to: 0
        epsilon: 0.2
    }

    Spring {
        id: inAnim
        target: root; property: "slide"; from: 1; to: 0
        epsilon: 0.002
    }

    SequentialAnimation {
        id: outAnim
        PauseAnimation { duration: root.delay }
        NumberAnimation {
            target: root; property: "slide"; to: 1
            duration: Notifs.leaveDuration; easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root; property: "shrink"; to: 0
            duration: root.collapse ? Notifs.collapseDuration : 0; easing.type: Easing.OutCubic
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
        x: root.drag + root.dir * root.slide * (root.width + 16)
        width: root.width
        height: implicitHeight
        opacity: (1 - root.slide) * (1 - 0.6 * Math.min(1, Math.abs(root.drag) / root.width))
        notif: root.notif
        // Крестик: убрать уведомление (всплывашка уйдёт сама по closed)
        onClosePressed: root.leave(() => root.notif.dismiss())
    }
}
