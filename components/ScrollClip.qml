import QtQuick

// Обрезает содержимое по maxWidth и прокручивает его по горизонтали
// колесом/тачпадом. Сам не едет. Клики проходят насквозь.
Item {
    id: root

    default property alias content: inner.data
    property real maxWidth: 150
    property real offset: 0

    readonly property real overflow: Math.max(0, inner.implicitWidth - maxWidth)

    implicitWidth: Math.min(inner.implicitWidth, maxWidth)
    implicitHeight: inner.implicitHeight
    clip: true

    onOverflowChanged: offset = Math.min(offset, overflow)

    function reset() {
        offset = 0
    }

    Row {
        id: inner
        x: -root.offset
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Behavior on x {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    WheelHandler {
        target: null
        enabled: root.overflow > 0
        onWheel: event => {
            // Тачпад даёт пиксели, колесо — щелчки по 120
            const d = event.pixelDelta.x || event.pixelDelta.y
                || (event.angleDelta.x || event.angleDelta.y) / 120 * 40
            root.offset = Math.max(0, Math.min(root.overflow, root.offset - d))
        }
    }
}
