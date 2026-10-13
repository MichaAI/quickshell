import QtQuick
import "../config"

// "Таблетка" на баре: фон, ховер, клики и скролл.
// MouseArea лежит ПОД контентом, чтобы интерактивные дети (иконки трея)
// получали свои клики.
Rectangle {
    id: root

    default property alias content: row.data
    property bool interactive: true
    property bool active: false
    property alias hovered: mouse.containsMouse

    signal clicked(var event)
    signal wheeled(real delta)

    implicitWidth: row.implicitWidth + Settings.pillPadding * 2
    implicitHeight: Settings.pillHeight
    radius: Settings.pillRadius
    color: active ? Theme.pillHover
         : (mouse.containsMouse && interactive ? Theme.mix(Theme.pillBg, Theme.pillHover, 0.6) : Theme.pillBg)

    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: event => root.clicked(event)
        onWheel: wheel => root.wheeled(wheel.angleDelta.y)
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
    }
}
