pragma ComponentBehavior: Bound
import QtQuick

// Обрезает содержимое по maxWidth и прокручивает его по горизонтали
// колесом/тачпадом. Сам не едет. Края, за которыми есть скрытый текст,
// растворяются в fadeColor (цвет фона под нами). Без слоёв и эффектов,
// чтобы текст рисовался нативно и не мылился. Клики и ховер проходят насквозь,
// пока не включён clickable.
Item {
    id: root

    default property alias content: inner.data
    property real maxWidth: 150
    property real fadeWidth: 24
    property color fadeColor: "black"
    property real offset: 0
    property bool clickable: false
    property alias spacing: inner.spacing
    property alias move: inner.move

    signal clicked()

    readonly property real overflow: Math.max(0, Math.ceil(inner.implicitWidth - maxWidth))

    implicitWidth: Math.min(inner.implicitWidth, maxWidth)
    implicitHeight: inner.implicitHeight
    clip: true

    onOverflowChanged: offset = Math.min(offset, overflow)

    function reset() {
        offset = 0
    }

    // Короткая вспышка — отклик на клик (например, «скопировано»)
    function flash() {
        flashAnim.restart()
    }

    SequentialAnimation {
        id: flashAnim
        NumberAnimation { target: inner; property: "opacity"; to: 0.35; duration: 90 }
        NumberAnimation { target: inner; property: "opacity"; to: 1; duration: 220 }
    }

    Row {
        id: inner
        x: -root.offset
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Behavior on x {
            Spring { bouncy: false }
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
        gradient: OkGradient {
            orientation: Gradient.Horizontal
            from: root.fadeColor
            to: Qt.alpha(root.fadeColor, 0)
        }
    }

    Fade {
        anchors.right: parent.right
        shown: root.offset < root.overflow
        gradient: OkGradient {
            orientation: Gradient.Horizontal
            from: Qt.alpha(root.fadeColor, 0)
            to: root.fadeColor
        }
    }

    // Отдельно от колеса: выключенная не трогает курсор и клики таблетки
    MouseArea {
        anchors.fill: parent
        visible: root.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
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
