pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../config"

// Живое небо в духе Breezy Weather: градиент по погоде и времени суток,
// солнце с дышащими ореолами или луна со звёздами, плывущие облака,
// дождь, снег, туман и вспышки грозы. Обрезку по скруглению делает родитель.
Item {
    id: root

    property string kind: "clear"   // clear partly cloudy fog drizzle rain snow thunder
    property bool isDay: true

    // Для PopoutReveal: проявлять сцену целиком, не разбирая на частицы
    readonly property bool revealWhole: true

    readonly property bool wet: kind === "drizzle" || kind === "rain" || kind === "thunder"
    readonly property bool overcast: wet || kind === "cloudy" || kind === "snow" || kind === "fog"
    // В пасмурную погоду светило не пропадает, а еле проглядывает за облаками
    readonly property bool dimLight: kind === "cloudy"
    readonly property bool showSun: isDay && (kind === "clear" || kind === "partly" || dimLight)
    readonly property bool showMoon: !isDay && (kind === "clear" || kind === "partly" || dimLight)
    readonly property real lightOpacity: dimLight ? 0.3 : 1

    // Небо: [верх, низ]. Достаточно тёмное, чтобы светлый текст читался
    readonly property var sky: {
        if (kind === "thunder") return ["#1f1a2e", "#3d3552"]
        if (wet) return isDay ? ["#34445a", "#5a6b80"] : ["#151b29", "#2b3446"]
        if (kind === "snow") return isDay ? ["#4d6283", "#8597b3"] : ["#1b2133", "#39425a"]
        if (kind === "fog") return isDay ? ["#4f5664", "#7b828f"] : ["#1d1f28", "#3a3d4a"]
        if (kind === "cloudy") return isDay ? ["#45556c", "#71839b"] : ["#181c2a", "#323849"]
        return isDay ? ["#2a5a9c", "#5d97d2"] : ["#0c1026", "#262c58"]
    }

    // Детерминированный «рандом», чтобы частицы не прыгали при пересоздании
    function rnd(i, salt) {
        const x = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453
        return x - Math.floor(x)
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: root.sky[0]; Behavior on color { ColorAnimation { duration: 600 } } }
            GradientStop { position: 1; color: root.sky[1]; Behavior on color { ColorAnimation { duration: 600 } } }
        }
    }

    // ===== Звёзды =====
    Repeater {
        model: root.isDay || root.overcast ? 0 : 28
        delegate: Rectangle {
            id: star
            required property int index
            readonly property real s: 1 + root.rnd(star.index, 3) * 1.6
            x: root.rnd(star.index, 1) * root.width
            y: root.rnd(star.index, 2) * root.height * 0.75
            width: s; height: s; radius: s / 2
            color: "white"
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                PauseAnimation { duration: root.rnd(star.index, 4) * 3000 }
                NumberAnimation { to: 0.15; duration: 900 + root.rnd(star.index, 5) * 1400; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.85; duration: 900 + root.rnd(star.index, 6) * 1400; easing.type: Easing.InOutSine }
            }
        }
    }

    // ===== Солнце: ядро и дышащие ореолы =====
    Item {
        id: sun
        visible: root.showSun
        opacity: root.lightOpacity
        Behavior on opacity { NumberAnimation { duration: 600 } }
        width: 52; height: 52
        x: root.width - 80
        y: 18

        Repeater {
            model: 3
            delegate: Rectangle {
                id: halo
                required property int index
                anchors.centerIn: parent
                width: parent.width * (1.6 + halo.index * 0.75)
                height: width
                radius: width / 2
                color: Theme.alpha(Theme.yellow, 0.10 - halo.index * 0.025)
                SequentialAnimation on scale {
                    running: sun.visible
                    loops: Animation.Infinite
                    PauseAnimation { duration: halo.index * 500 }
                    NumberAnimation { from: 0.92; to: 1.08; duration: 2600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.08; to: 0.92; duration: 2600; easing.type: Easing.InOutSine }
                }
            }
        }

        // Лучи медленно вращаются
        Item {
            anchors.fill: parent
            RotationAnimation on rotation {
                running: sun.visible
                from: 0; to: 360
                duration: 60000
                loops: Animation.Infinite
            }
            Repeater {
                model: 12
                delegate: Rectangle {
                    id: ray
                    required property int index
                    x: parent.width / 2 - width / 2
                    y: -14
                    width: 3; height: 10; radius: 1.5
                    color: Theme.alpha(Theme.yellow, 0.55)
                    transform: Rotation {
                        origin.x: 1.5
                        origin.y: 26 + 14
                        angle: ray.index * 30
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: "#fff3c4" }
                GradientStop { position: 1; color: Theme.peach }
            }
        }
    }

    // ===== Луна =====
    Item {
        id: moon
        visible: root.showMoon
        opacity: root.lightOpacity
        Behavior on opacity { NumberAnimation { duration: 600 } }
        width: 40; height: 40
        x: root.width - 74
        y: 20

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 2.6; height: width; radius: width / 2
            color: Theme.alpha(Theme.lavender, 0.08)
            SequentialAnimation on scale {
                running: moon.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0.9; to: 1.1; duration: 3200; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.1; to: 0.9; duration: 3200; easing.type: Easing.InOutSine }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#e8e6f5"
        }
        // Кратеры
        Repeater {
            model: [[9, 10, 8], [22, 20, 6], [14, 25, 4]]
            delegate: Rectangle {
                id: crater
                required property var modelData
                x: crater.modelData[0]; y: crater.modelData[1]
                width: crater.modelData[2]; height: width; radius: width / 2
                color: "#cfcbe3"
            }
        }
    }

    // ===== Облака =====
    component Cloud: Item {
        id: cloud
        property color tint: "white"
        // Круги рисуются непрозрачными, прозрачность — всему облаку разом,
        // иначе на стыках кругов темнеет
        property real alpha: 0.2
        opacity: alpha
        layer.enabled: true
        // Сглаживание слоя: без него текстура липнет к целым пикселям,
        // и медленное облако ползёт рывками
        layer.smooth: true
        property real phase: 0          // начальная позиция, 0…1
        property int period: 60000      // полный проход, мс
        property real span: 0           // ширина неба
        property real t
        readonly property real p: (t + phase) % 1

        width: 120; height: 48
        x: -width + (span + width) * p

        NumberAnimation on t {
            from: 0; to: 1
            duration: cloud.period
            loops: Animation.Infinite
        }

        Rectangle { x: 0; y: parent.height * 0.45; width: parent.width; height: parent.height * 0.55; radius: height / 2; color: cloud.tint }
        Rectangle { x: parent.width * 0.14; y: parent.height * 0.18; width: parent.width * 0.38; height: width; radius: width / 2; color: cloud.tint }
        Rectangle { x: parent.width * 0.40; y: 0; width: parent.width * 0.42; height: width; radius: width / 2; color: cloud.tint }
    }

    readonly property int cloudCount: kind === "partly" ? 2 : (overcast ? 5 : 0)

    Repeater {
        model: root.cloudCount
        delegate: Cloud {
            id: skyCloud
            required property int index
            readonly property real depth: root.rnd(skyCloud.index, 7)
            // Своя полоса по высоте, перемешанная относительно порядка по x,
            // чтобы соседи по небу не шли одной линией
            readonly property int lane: (skyCloud.index * 3) % root.cloudCount
            width: 80 + depth * 70
            height: width * 0.4
            y: -8 + (lane + root.rnd(skyCloud.index, 8) * 0.6) / root.cloudCount
                 * root.height * (root.kind === "partly" ? 0.45 : 0.5)
            span: root.width
            // Равномерно по ширине с небольшим разбросом, а не как выпадет
            phase: (skyCloud.index + root.rnd(skyCloud.index, 9) * 0.5) / root.cloudCount
            // Скорости близкие: сильно разные нагоняли друг друга и сбивались в кучу
            period: 62000 - depth * 12000
            tint: root.wet ? (root.isDay ? "#c3cede" : "#8f9ab0") : "white"
            alpha: root.kind === "partly" ? (root.isDay ? 0.22 : 0.1) + depth * 0.14
                 : root.wet ? 0.12 + depth * 0.12
                 : (root.isDay ? 0.12 : 0.07) + depth * 0.12
        }
    }

    // ===== Туман: полупрозрачные полосы качаются вбок =====
    Repeater {
        model: root.kind === "fog" ? 5 : 0
        delegate: Rectangle {
            id: fogBand
            required property int index
            property real t
            width: root.width * 1.4
            height: 18 + root.rnd(fogBand.index, 10) * 18
            radius: height / 2
            y: root.height * (0.2 + fogBand.index * 0.16)
            x: -root.width * 0.2 + Math.sin(t * Math.PI * 2) * root.width * 0.12
            color: Qt.rgba(1, 1, 1, 0.07 + root.rnd(fogBand.index, 11) * 0.08)
            NumberAnimation on t {
                from: root.rnd(fogBand.index, 12); to: root.rnd(fogBand.index, 12) + 1
                duration: 9000 + root.rnd(fogBand.index, 13) * 6000
                loops: Animation.Infinite
            }
        }
    }

    // ===== Дождь: косые капли =====
    Repeater {
        model: root.kind === "drizzle" ? 30 : (root.kind === "rain" ? 70 : (root.kind === "thunder" ? 90 : 0))
        delegate: Rectangle {
            id: drop
            required property int index
            property real t
            readonly property real p: (t + root.rnd(drop.index, 14)) % 1
            readonly property real x0: root.rnd(drop.index, 15) * (root.width + 40)
            width: 1.5
            height: root.kind === "drizzle" ? 7 : 11 + root.rnd(drop.index, 16) * 7
            radius: 0.75
            rotation: 15
            x: x0 - p * root.height * 0.27
            y: -20 + p * (root.height + 40)
            color: Qt.rgba(0.86, 0.9, 0.96, 0.25 + root.rnd(drop.index, 17) * 0.3)
            NumberAnimation on t {
                from: 0; to: 1
                duration: (root.kind === "drizzle" ? 1100 : 650) + root.rnd(drop.index, 18) * 300
                loops: Animation.Infinite
            }
        }
    }

    // ===== Снег: хлопья падают и покачиваются =====
    Repeater {
        model: root.kind === "snow" ? 50 : 0
        delegate: Rectangle {
            id: flake
            required property int index
            property real t
            readonly property real p: (t + root.rnd(flake.index, 19)) % 1
            readonly property real s: 2 + root.rnd(flake.index, 20) * 3.5
            width: s; height: s; radius: s / 2
            x: root.rnd(flake.index, 21) * root.width + Math.sin((p * 3 + root.rnd(flake.index, 22)) * Math.PI * 2) * 8
            y: -10 + p * (root.height + 20)
            color: Qt.rgba(1, 1, 1, 0.5 + root.rnd(flake.index, 23) * 0.4)
            NumberAnimation on t {
                from: 0; to: 1
                duration: 6000 + root.rnd(flake.index, 24) * 5000
                loops: Animation.Infinite
            }
        }
    }

    // ===== Гроза: молния и вспышка неба =====
    Shape {
        id: bolt
        visible: root.kind === "thunder"
        opacity: 0
        x: root.width * 0.55
        y: 6
        width: 34; height: 70
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0
            fillColor: "#fff6d6"
            startX: 18; startY: 0
            PathLine { x: 4; y: 38 }
            PathLine { x: 15; y: 38 }
            PathLine { x: 8; y: 70 }
            PathLine { x: 30; y: 28 }
            PathLine { x: 19; y: 28 }
            PathLine { x: 28; y: 0 }
            PathLine { x: 18; y: 0 }
        }
    }

    Rectangle {
        id: flash
        anchors.fill: parent
        color: "white"
        opacity: 0
    }

    SequentialAnimation {
        id: strike
        ParallelAnimation {
            NumberAnimation { target: flash; property: "opacity"; to: 0.35; duration: 60 }
            NumberAnimation { target: bolt; property: "opacity"; to: 1; duration: 40 }
        }
        NumberAnimation { target: flash; property: "opacity"; to: 0.05; duration: 90 }
        NumberAnimation { target: flash; property: "opacity"; to: 0.25; duration: 50 }
        ParallelAnimation {
            NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 420; easing.type: Easing.OutQuad }
            NumberAnimation { target: bolt; property: "opacity"; to: 0; duration: 320; easing.type: Easing.OutQuad }
        }
    }

    Timer {
        running: root.kind === "thunder"
        interval: 2500
        repeat: true
        onTriggered: {
            bolt.x = root.width * (0.35 + Math.random() * 0.4)
            strike.restart()
            interval = 2500 + Math.random() * 4500
        }
    }

    // Затемнение слева и снизу под текст
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.22) }
            GradientStop { position: 0.6; color: "transparent" }
        }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.35; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.32) }
        }
    }
}
