import QtQuick

// Обрезает содержимое по maxWidth и прокручивает его по горизонтали
// колесом/тачпадом. Сам не едет. Края, за которыми есть скрытый текст,
// растворяются в fadeColor (цвет фона под нами). Без слоёв и эффектов,
// чтобы текст рисовался нативно и не мылился. Клики и ховер проходят насквозь.
Item {
    id: root

    default property alias content: inner.data
    property real maxWidth: 150
    property real fadeWidth: 24
    property color fadeColor: "black"
    property real offset: 0

    readonly property real overflow: Math.max(0, Math.ceil(inner.implicitWidth - maxWidth))

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

    component Fade: Rectangle {
        property bool shown: false
        width: Math.min(root.fadeWidth, root.width / 2)
        height: root.height
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    Fade {
        anchors.left: parent.left
        shown: root.offset > 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.fadeColor }
            GradientStop { position: 1; color: Qt.alpha(root.fadeColor, 0) }
        }
    }

    Fade {
        anchors.right: parent.right
        shown: root.offset < root.overflow
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(root.fadeColor, 0) }
            GradientStop { position: 1; color: root.fadeColor }
        }
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
            // Тачпад даёт пиксели, колесо — щелчки по 120.
            // Целые пиксели — чтобы текст в покое стоял ровно по сетке.
            const d = wheel.pixelDelta.x || wheel.pixelDelta.y
                || (wheel.angleDelta.x || wheel.angleDelta.y) / 120 * 40
            root.offset = Math.round(Math.max(0, Math.min(root.overflow, root.offset - d)))
        }
    }
}
