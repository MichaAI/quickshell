import QtQuick
import "../config"

// Слайдер. Стиль и толщина — Settings.sliderStyle и sliderSize:
//   expressive — MD3 Expressive: дорожка из двух частей, между ними ручка-
//                палочка с зазором, в конце точка-стоп (токены MDC Android);
//   pill       — пилюля в пилюле, как в шторке Android 12–15: край
//                активной части и есть ручка.
// wavy — всегда MD3E-волна, как у LinearWavyProgressIndicator: бежит, пока
// moving, и разглаживается, когда стоит или у самых краёв.
Item {
    id: root

    property real value: 0          // 0..1
    property bool enabled: true
    property real wheelStep: 0.05
    // false — колесо не трогает, прокрутка уходит списку под слайдером
    property bool wheelEnabled: true
    property bool wavy: false
    property bool moving: true
    // Текст пузырька над ручкой, пока тянут
    property var valueText: v => Math.round(v * 100) + "%"
    property color colorFrom: Theme.gradStart
    property color colorTo: Theme.gradEnd

    signal moved(real value)

    // Пока тянут, ручка едет за мышью сразу, а наружу (PipeWire, MPRIS)
    // значение уходит не чаще раза в sendEvery мс и только если сдвинулось
    // хотя бы на sendStep; последнее положение отправляется при отпускании.
    // live: false — только при отпускании (то, что применяется медленно)
    property bool live: true
    property int sendEvery: 60
    property real sendStep: 0.005
    property real held: NaN         // положение под мышью, пока тянут
    property real sent: NaN         // последнее отправленное
    function send(force) {
        if (isNaN(held) || (!force && Math.abs(held - sent) < sendStep) || held === sent)
            return
        sent = held
        moved(held)
        throttle.restart()
    }
    Timer {
        id: throttle
        interval: root.sendEvery
        onTriggered: root.send(false)
    }
    // Мышь главнее: после отпускания ручка стоит там, где её бросили,
    // пока снаружи не придёт значение рядом с ним (не дальше holdTolerance).
    // Старые значения, которыми источник ещё тянет назад (kdeconnect), ручку
    // не дёргают. Первые holdMin мс не верим даже совпадению: своё значение
    // может прийти эхом раньше чужого старого. Не сошлось за holdMax мс —
    // значит, источник не согласился, показываем его
    property real holdTolerance: 0.01
    property int holdMin: 600
    property int holdMax: 1500
    function tryUnhold() {
        if (!unhold.running || settle.running || Math.abs(value - held) > holdTolerance)
            return
        unhold.stop()
        held = NaN
    }
    Timer {
        id: unhold
        interval: root.holdMax
        onTriggered: root.held = NaN
    }
    Timer {
        id: settle
        interval: root.holdMin
        onTriggered: root.tryUnhold()
    }
    onValueChanged: tryUnhold()

    readonly property bool pill: !wavy && Settings.sliderStyle === "pill"
    readonly property real trackH: wavy ? 4 : Theme.sliderSpec[0]
    readonly property real corner: wavy ? 2 : Math.min(Theme.sliderSpec[1], trackH / 2)
    readonly property real handleH: wavy ? 20 : pill ? trackH : Theme.sliderSpec[2]
    readonly property real gap: 6
    readonly property real v: Math.max(0, Math.min(1, isNaN(held) ? value : held))
    // Центр ручки ходит между краями с отступом в полручки (ручка 4 px)
    readonly property real cx: 2 + v * (width - 4)
    readonly property real activeEnd: cx - 2 - gap
    readonly property real inactiveStart: cx + 2 + gap

    implicitHeight: handleH
    implicitWidth: 160

    // ===== pill =====
    Rectangle {
        visible: root.pill
        anchors.verticalCenter: parent.verticalCenter
        width: root.width
        height: root.trackH
        radius: height / 2
        color: Theme.surface0
    }
    Rectangle {
        visible: root.pill
        anchors.verticalCenter: parent.verticalCenter
        width: root.trackH + root.v * (root.width - root.trackH)
        height: root.trackH
        radius: height / 2
        gradient: OkGradient {
            orientation: Gradient.Horizontal
            from: root.colorFrom
            to: root.colorTo
        }
    }

    // ===== expressive и волна =====
    // Активная часть: плоская
    Rectangle {
        visible: !root.pill && !root.wavy && width > 0
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.activeEnd)
        height: root.trackH
        topLeftRadius: root.corner
        bottomLeftRadius: root.corner
        topRightRadius: 2
        bottomRightRadius: 2
        gradient: OkGradient {
            orientation: Gradient.Horizontal
            from: root.colorFrom
            to: root.colorTo
        }
    }

    // …или волна
    ShaderEffect {
        id: wave
        visible: root.wavy && width > thick
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.activeEnd)
        height: 2 * 3 + thick + 2

        property size size: Qt.size(width, height)
        property real amp: root.wavy && root.moving && root.value > 0.1 && root.value < 0.95 ? 3 : 0
        property real wavelength: 40
        property real phase: 0
        property real thick: root.trackH
        property color c0: root.colorFrom
        property color c1: root.colorTo
        fragmentShader: "../assets/shaders/wave.frag.qsb"

        Behavior on amp { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        // Длина волны в секунду, без рывка при паузе
        FrameAnimation {
            running: wave.visible && wave.amp > 0
            onTriggered: wave.phase = (wave.phase + frameTime) % 1
        }
    }

    // Неактивная часть
    Rectangle {
        visible: !root.pill && width > 0
        x: root.inactiveStart
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.width - root.inactiveStart)
        height: root.trackH
        topLeftRadius: Math.min(2, root.corner)
        bottomLeftRadius: Math.min(2, root.corner)
        topRightRadius: root.corner
        bottomRightRadius: root.corner
        color: Theme.surface0
    }

    // Стоп в конце дорожки
    Rectangle {
        readonly property real pad: root.wavy ? 0 : root.gap
        visible: !root.pill && x >= root.inactiveStart + 2
        x: root.width - pad - width
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: 4
        radius: 2
        color: root.colorTo
    }

    // Ручка: на нажатии худеет до 2 px
    Rectangle {
        visible: !root.pill
        x: root.cx - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: mouse.pressed ? 2 : 4
        height: root.handleH
        radius: width / 2
        color: root.colorTo
        Behavior on width { NumberAnimation { duration: 100 } }
    }

    ValueBubble {
        target: root
        handleX: root.pill ? root.trackH / 2 + root.v * (root.width - root.trackH) : root.cx
        handleTop: (root.height - root.handleH) / 2
        shown: mouse.pressed
        text: root.valueText(root.v)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor

        function report(mx) {
            const v = root.pill ? (mx - root.trackH / 2) / (root.width - root.trackH)
                                : (mx - 2) / (root.width - 4)
            unhold.stop()
            root.held = Math.max(0, Math.min(1, v))
            if (root.live && !throttle.running)
                root.send(false)
        }

        onPressed: event => {
            root.sent = NaN
            report(event.x)
        }
        onPositionChanged: event => { if (pressed) report(event.x) }
        onReleased: {
            throttle.stop()
            root.send(true)
            unhold.restart()
            settle.restart()
        }
        onCanceled: {
            throttle.stop()
            root.send(true)
            unhold.restart()
            settle.restart()
        }
        onWheel: wheel => {
            if (!root.wheelEnabled) {
                wheel.accepted = false
                return
            }
            const d = wheel.angleDelta.y > 0 ? root.wheelStep : -root.wheelStep
            root.moved(Math.max(0, Math.min(1, root.value + d)))
        }
    }
}
