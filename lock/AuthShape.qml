import QtQuick
import "../config"
import "../components"
import "../components/Shapes.js" as Shapes

// Индикатор проверки пароля поверх поля ввода (лежит на поле, размер —
// как у поля). Пока PAM думает — фигура MD3E LoadingIndicator чуть больше
// поля, перетекает по циклу форм и крутится; рамка цвета плитки отделяет
// её от поля. Неудача: фигура подпрыгивает, сжимается в каплю, падает на
// верхний край поля и растекается по рамке красным — тогда errorShown и
// impact() (тряска). Успех: фигура схлопывается.
Item {
    id: root

    property bool busy: false
    property string error: ""
    property real fieldRadius: height / 2
    property color backdrop: Theme.crust

    property bool errorShown: false
    readonly property bool failing: fail.running
    signal impact()

    readonly property real size: height / 2 + 7     // радиус: чуть больше поля

    onErrorChanged: if (error === "") errorShown = false
    onBusyChanged: {
        if (busy) {
            fail.stop()
            errorShown = false
            blob.lift = 0
            blob.from = Shapes.softBurst
            blob.to = Shapes.softBurst
            blob.morph = 0
            blob.opacity = 1
            grow.restart()
        } else {
            // Lock.qml снимает busy раньше, чем пишет error, — смотрим,
            // чем кончилось, уже после обработчика
            Qt.callLater(root.settle)
        }
    }

    function settle() {
        if (busy)
            return
        grow.stop()
        if (error !== "")
            fail.restart()
        else
            vanish.restart()
    }

    MorphShape {
        id: blob
        anchors.centerIn: parent
        anchors.verticalCenterOffset: lift
        width: 120
        height: 120
        radius: 0
        visible: radius > 0.5
        outline: 4
        outlineColor: root.backdrop

        property real lift: 0
        property int step: 0

        // Цикл форм LoadingIndicator: каждые 650 мс — к следующей
        Timer {
            interval: 650
            repeat: true
            running: root.busy
            onTriggered: {
                blob.step = (blob.step + 1) % Shapes.loading.length
                blob.from = blob.to
                blob.to = Shapes.loading[blob.step]
                blob.morph = 0
                morphAnim.restart()
            }
        }
        NumberAnimation {
            id: morphAnim
            target: blob; property: "morph"; to: 1
            duration: 500; easing.type: Easing.InOutCubic
        }
        FrameAnimation {
            running: blob.visible && !fail.running
            onTriggered: blob.turn = (blob.turn + frameTime * (root.busy ? 0.45 : 0.15)) % 1
        }
    }

    // Красная рамка, расползающаяся из точки падения капли
    MorphShape {
        id: sweep
        anchors.fill: parent
        visible: false
        boxWidth: width
        boxHeight: height
        boxRadius: root.fieldRadius
        boxMix: 1
        band: 2
        colorFrom: Theme.red
        colorTo: Theme.red
        revealOn: true
        revealY: -height / 2
    }

    // Появление: фигура вырастает из слетевшихся точек
    NumberAnimation {
        id: grow
        target: blob; property: "radius"; from: 0; to: root.size
        duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.6
    }

    // Успех: схлопнуться
    ParallelAnimation {
        id: vanish
        NumberAnimation { target: blob; property: "radius"; to: 0; duration: 220; easing.type: Easing.InCubic }
        NumberAnimation { target: blob; property: "opacity"; to: 0; duration: 220 }
    }

    // Неудача: подпрыгнуть, сжаться в каплю, упасть в рамку и растечься
    SequentialAnimation {
        id: fail
        ScriptAction {
            script: {
                morphAnim.stop()
                blob.from = blob.to
                blob.to = Shapes.drop
                blob.morph = 0
                // Капля — стоймя: доворачиваем до ближайших пол-оборота
                dropTurn.to = Math.ceil(blob.turn * 2) / 2
            }
        }
        ParallelAnimation {
            NumberAnimation { id: dropTurn; target: blob; property: "turn"; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: blob; property: "lift"; to: -root.height * 0.9; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: blob; property: "morph"; to: 1; duration: 260; easing.type: Easing.InOutCubic }
            NumberAnimation { target: blob; property: "radius"; to: 6; duration: 260; easing.type: Easing.InOutCubic }
        }
        NumberAnimation { target: blob; property: "lift"; to: -root.height / 2; duration: 200; easing.type: Easing.InQuad }
        ScriptAction {
            script: {
                sweep.revealRadius = 0
                sweep.visible = true
            }
        }
        ParallelAnimation {
            NumberAnimation { target: blob; property: "radius"; to: 0; duration: 90 }
            NumberAnimation { target: sweep; property: "revealRadius"; to: root.width; duration: 380; easing.type: Easing.OutCubic }
        }
        ScriptAction {
            script: {
                root.errorShown = true
                sweep.visible = false
                root.impact()
            }
        }
    }
}
