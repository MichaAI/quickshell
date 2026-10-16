import QtQuick
import "../config"

// Кольцо прогресса MD3 Expressive (CircularWavyProgressIndicator):
// активная дуга — волна, остаток — ровная дорожка с зазорами. Размеры —
// токены Compose для 48 px (линия 4, амплитуда 1.6, длина волны 15,
// зазор 4); scale — во сколько раз крупнее. Волна бежит, пока moving, и
// разглаживается, когда стоит или у самых краёв.
ShaderEffect {
    id: ring

    property real value: 0          // 0..1
    property bool moving: true
    property real scale_: width / 48
    property color from: Theme.gradStart
    property color to: Theme.gradEnd

    implicitWidth: 48
    implicitHeight: 48

    property size size: Qt.size(width, height)
    property real progress: Math.max(0, Math.min(1, value))
    property real amp: moving && value > 0.1 && value < 0.95 ? 1.6 * scale_ : 0
    property real wavelength: 15 * scale_
    property real phase: 0
    property real thick: 4 * scale_
    property real gap: 4 * scale_
    property color c0: from
    property color c1: to
    property color track: Theme.surface0
    fragmentShader: Qt.resolvedUrl("../assets/shaders/ring.frag.qsb")

    Behavior on progress { Spring { epsilon: 0.002 } }
    Behavior on amp { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

    // Длина волны в секунду, без рывка при остановке
    FrameAnimation {
        running: ring.visible && ring.amp > 0
        onTriggered: ring.phase = (ring.phase + frameTime) % 1
    }
}
