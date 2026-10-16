import QtQuick
import "../config"

// Растяжка у края списка, как в Android 12+ (MD3): прокрутка колесом или
// тачпадом дальше края не упирается в стену, а тянет содержимое — оно
// растягивается от этого края, и чем дальше тянут, тем туже. Отпустили —
// пружиной обратно.
//
// Кладётся рядом со списком поверх него: Overscroll { flick: list }.
// Колесо не забирает — список листается как обычно.
Item {
    id: o

    required property Flickable flick
    property bool horizontal: false
    // Насколько растягивается при бесконечной тяге
    property real strength: 0.12

    anchors.fill: flick

    // Натяжение, px: минус — за началом, плюс — за концом
    property real pull: 0
    readonly property real size: horizontal ? flick.width : flick.height
    readonly property real stretch: strength * (1 - Math.exp(-Math.abs(pull) / Math.max(1, size * 0.3)))
    readonly property bool scrollable: horizontal ? flick.contentWidth > flick.width + 1
                                                  : flick.contentHeight > flick.height + 1

    // Растягиваем содержимое (а не сам список: тогда поехала бы и обрезка)
    // от того края, за который тянут
    Scale {
        id: sc
        origin.x: o.horizontal ? (o.pull < 0 ? o.flick.contentX : o.flick.contentX + o.flick.width) : 0
        origin.y: o.horizontal ? 0 : (o.pull < 0 ? o.flick.contentY : o.flick.contentY + o.flick.height)
        xScale: o.horizontal ? 1 + o.stretch : 1
        yScale: o.horizontal ? 1 : 1 + o.stretch
    }
    Component.onCompleted: flick.contentItem.transform = Array.from(flick.contentItem.transform).concat([sc])

    WheelHandler {
        target: null
        blocking: false
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (!o.scrollable)
                return
            // Вниз/вправо по содержимому — плюс
            let d = o.horizontal
                ? -(event.pixelDelta.x || event.angleDelta.x / 4 || event.angleDelta.y / 4)
                : -(event.pixelDelta.y || event.angleDelta.y / 4)
            const atStart = o.horizontal ? o.flick.atXBeginning : o.flick.atYBeginning
            const atEnd = o.horizontal ? o.flick.atXEnd : o.flick.atYEnd
            // Обратно к краю — отпускаем натяжение, а не листаем
            if ((o.pull < 0 && d > 0) || (o.pull > 0 && d < 0)) {
                o.pull = Math.abs(d) >= Math.abs(o.pull) ? 0 : o.pull + d
            } else if ((atStart && d < 0) || (atEnd && d > 0)) {
                back.stop()
                o.pull = Math.max(-o.size, Math.min(o.size, o.pull + d * 0.6))
            } else {
                return
            }
            release.restart()
        }
    }

    // Пальцы убрали (или колесо замолчало) — пружиной на место
    Timer {
        id: release
        interval: 120
        onTriggered: back.start()
    }
    SpringAnimation {
        id: back
        target: o; property: "pull"; to: 0
        spring: Motion.calmSpring; damping: Motion.calmDamping; epsilon: 0.5
    }
}
