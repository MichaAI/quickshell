import QtQuick
import QtQuick3D
import QtQuick3D.AssetUtils
import ".."

// Крутящаяся 3D-модель вместо аватарки, перекрашенная крупным дизерингом
// в цвета темы. Грузится Loader'ом: если в quickshell нет QtQuick3D,
// загрузка просто не удастся и лок покажет обычную ~/.face.
Item {
    id: root

    property url model
    readonly property bool ready: loader.status === RuntimeLoader.Success

    View3D {
        id: view
        anchors.fill: parent

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.NoAA
        }

        PerspectiveCamera {
            position: Qt.vector3d(0, 0, 300)
            clipNear: 1
            clipFar: 3000
        }
        DirectionalLight {
            eulerRotation: Qt.vector3d(-30, -35, 0)
            brightness: 1.0
        }
        // Контровой свет сзади — чтобы силуэт не сливался с тенью
        DirectionalLight {
            eulerRotation: Qt.vector3d(15, 150, 0)
            brightness: 0.35
        }

        Node {
            NumberAnimation on eulerRotation.y {
                from: 0; to: 360
                duration: 14000
                loops: Animation.Infinite
            }

            // Любую модель вписываем в один размер и ставим центром в начало
            // координат: тогда она крутится вокруг себя, а не по орбите
            RuntimeLoader {
                id: loader
                source: root.model

                readonly property vector3d lo: bounds.minimum
                readonly property vector3d hi: bounds.maximum
                readonly property real extent: Math.max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 0.0001)
                readonly property real k: 190 / extent

                scale: Qt.vector3d(k, k, k)
                position: Qt.vector3d(-(lo.x + hi.x) / 2 * k, -(lo.y + hi.y) / 2 * k, -(lo.z + hi.z) / 2 * k)
            }
        }

        layer.enabled: true
        layer.effect: ShaderEffect {
            fragmentShader: "../assets/shaders/dither.frag.qsb"
            property vector2d size: Qt.vector2d(width, height)
            property real pixel: 4
            property color c0: Theme.surface1
            property color c1: Theme.mauve
            property color c2: Theme.pink
            property color c3: Theme.rosewater
        }
    }
}
