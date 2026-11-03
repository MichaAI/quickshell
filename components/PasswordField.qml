pragma ComponentBehavior: Bound
import QtQuick
import "../config"

// Поле пароля в стиле лока: точки выпрыгивают пружиной, на отправке
// слетаются в центр, из них растёт AuthShape; ошибка — тряска и красная
// рамка. Ввод — не здесь: хозяин держит свой (невидимый) TextInput и
// отдаёт состояние через ctx:
//   ctx.text, ctx.length, ctx.busy, ctx.error
// echo — показывать сам текст вместо точек (не пароль, а, скажем, имя)
Rectangle {
    id: root

    required property var ctx
    property string placeholder: "Пароль"
    property bool echo: false
    property color backdrop: root.backdrop
    implicitWidth: 300
    implicitHeight: 50
    radius: height / 2
    color: Theme.base
    border.width: 2
    border.color: auth.errorShown ? Theme.red
                : root.ctx.busy || auth.failing ? Theme.surface2 : Theme.mauve
    Behavior on border.color { ColorAnimation { duration: 150 } }

    // Тряска при ошибке: пинок вбок, пружина почти без затухания
    property real shake: 0
    x: shake
    SpringAnimation {
        id: shakeAnim
        target: root; property: "shake"; to: 0
        spring: Motion.shakeSpring; damping: Motion.shakeDamping; epsilon: 0.2
    }

    Text {
        anchors.centerIn: parent
        visible: root.ctx.length === 0 && !root.ctx.busy
                 && (auth.errorShown || root.ctx.error === "")
        text: auth.errorShown ? root.ctx.error : root.placeholder
        font.family: Theme.font
        font.pixelSize: 13
        font.italic: true
        color: auth.errorShown ? Theme.red : Theme.overlay0
    }

    // Точки: каждая выпрыгивает пружиной. Модель меняем по
    // одной точке — целочисленная модель Repeater'а
    // пересоздавала бы все точки на каждое нажатие
    ListModel { id: dots }

    function syncDots() {
        const n = Math.min(root.ctx.length, 256)
        while (dots.count < n) dots.append({})
        while (dots.count > n) dots.remove(dots.count - 1)
    }
    Component.onCompleted: syncDots()
    Connections {
        target: root.ctx
        function onLengthChanged() { root.syncDots() }
    }

    // Не влезающие точки уезжают влево за край, как текст в
    // обычном поле ввода; назад — колесом
    // Не пароль — сам текст
    Text {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.width - 2 * root.radius)
        visible: root.echo
        text: root.ctx.text
        elide: Text.ElideLeft
        font.family: Theme.font
        font.pixelSize: 14
        color: Theme.text
    }

    ScrollClip {
        id: dotsClip
        visible: !root.echo
        anchors.centerIn: parent
        maxWidth: root.width - 2 * root.radius
        fadeColor: root.color
        spacing: 7
        // Остальные точки плавно отъезжают, давая место новой
        move: Transition { Spring { properties: "x"; bouncy: false } }
        // Набор и стирание всегда возвращают к последней точке
        onOverflowChanged: offset = overflow

        Repeater {
            model: dots

            Rectangle {
                id: dot
                required property int index
                width: 9; height: 9
                radius: 4.5
                color: Theme.mix(Theme.gradStart, Theme.gradEnd,
                                 dots.count > 1 ? index / (dots.count - 1) : 0)
                Behavior on color { ColorAnimation { duration: 150 } }
                scale: 0
                Component.onCompleted: scale = 1
                Behavior on scale { Spring { epsilon: 0.002 } }

                // Отправили — точки по очереди слетаются в центр
                // поля и тают: из них вырастает фигура AuthShape
                property real gather: 0
                property real toCenter: 0
                opacity: 1 - gather
                transform: Translate { x: dot.gather * dot.toCenter }
                SequentialAnimation {
                    id: gatherAnim
                    PauseAnimation { duration: Math.max(0, dot.index) * 12 }
                    NumberAnimation { target: dot; property: "gather"; to: 1; duration: 260; easing.type: Easing.InCubic }
                }
                Connections {
                    target: root.ctx
                    function onBusyChanged() {
                        if (!root.ctx.busy)
                            return
                        dot.toCenter = root.width / 2 - dot.mapToItem(root, dot.width / 2, 0).x
                        gatherAnim.restart()
                    }
                }
            }
        }
    }

    AuthShape {
        id: auth
        anchors.fill: parent
        busy: root.ctx.busy
        error: root.ctx.error
        fieldRadius: root.radius
        backdrop: root.backdrop
        onImpact: {
            root.shake = Motion.shakeDistance
            shakeAnim.restart()
        }
    }
}
