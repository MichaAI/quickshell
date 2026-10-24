import QtQuick

// Смена текста через затухание: старый гаснет, новый проявляется.
//   Behavior on text { TextFade { target: <этот же элемент> } }
// PropertyAction без цели — от Behavior: он и подменяет текст посередине
SequentialAnimation {
    id: root

    property Item target
    property int duration: 140

    NumberAnimation {
        target: root.target
        property: "opacity"
        to: 0
        duration: root.duration
        easing.type: Easing.InQuad
    }
    PropertyAction {}
    NumberAnimation {
        target: root.target
        property: "opacity"
        to: 1
        duration: root.duration
        easing.type: Easing.OutQuad
    }
}
