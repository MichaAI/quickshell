import QtQuick
import QtQuick.Effects

// Обрезает содержимое по maxWidth и прокручивает его по горизонтали
// колесом/тачпадом. Сам не едет. Края, за которыми есть скрытый текст,
// плавно растворяются. Клики и ховер проходят насквозь.
Item {
    id: root

    default property alias content: inner.data
    property real maxWidth: 150
    property real fadeWidth: 24
    property real offset: 0

    readonly property real overflow: Math.max(0, inner.implicitWidth - maxWidth)

    implicitWidth: Math.min(inner.implicitWidth, maxWidth)
    implicitHeight: inner.implicitHeight

    onOverflowChanged: offset = Math.min(offset, overflow)

    function reset() {
        offset = 0
    }

    Item {
        id: view
        anchors.fill: parent
        clip: true
        // Пока всё влезает — рисуем напрямую, без эффекта
        visible: root.overflow === 0
        layer.enabled: root.overflow > 0

        Row {
            id: inner
            x: -root.offset
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Behavior on x {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }
    }

    // Маска: альфа 0 у края, где что-то спрятано, 1 — где текст кончился
    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        property real fadeL: root.offset > 0.5 ? 1 : 0
        property real fadeR: root.offset < root.overflow - 0.5 ? 1 : 0
        Behavior on fadeL { NumberAnimation { duration: 150 } }
        Behavior on fadeR { NumberAnimation { duration: 150 } }

        readonly property real edge: width > 0 ? Math.min(0.45, root.fadeWidth / width) : 0

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 1 - mask.fadeL) }
            GradientStop { position: mask.edge; color: "white" }
            GradientStop { position: 1 - mask.edge; color: "white" }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 1 - mask.fadeR) }
        }
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.overflow > 0
        source: view
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }

    // Только колесо: кнопки не принимает, ховер не перехватывает
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            if (root.overflow === 0) {
                wheel.accepted = false
                return
            }
            // Тачпад даёт пиксели, колесо — щелчки по 120
            const d = wheel.pixelDelta.x || wheel.pixelDelta.y
                || (wheel.angleDelta.x || wheel.angleDelta.y) / 120 * 40
            root.offset = Math.max(0, Math.min(root.overflow, root.offset - d))
        }
    }
}
