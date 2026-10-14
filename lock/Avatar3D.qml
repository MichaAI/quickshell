import QtQuick
import QtQuick3D
import QtQuick3D.AssetUtils
import "../config"

// Крутящаяся 3D-модель вместо аватарки, перекрашенная крупным дизерингом
// в цвета темы. Грузится Loader'ом: если в quickshell нет QtQuick3D,
// загрузка просто не удастся и лок покажет обычную ~/.face.
//
// model — сам файл модели (.glb/.gltf/.fbx/.obj): его RuntimeLoader
// покажет без анимаций. scene — .qml, который сделал из модели balsam
// (Lock.qml делает её сам, если есть balsam): только так проигрываются
// анимации. Если сцена
// задана и открылась — берём её, иначе модель.
Item {
    id: root

    property url model
    property url scene
    property real modelSize: Settings.lockModelSize
    property int spinMs: Settings.lockSpinMs
    property string animation: Settings.lockAnimation
    property real animationSpeed: Settings.lockAnimationSpeed

    readonly property bool converted: scene.toString() !== "" && sceneLoader.status !== Loader3D.Error
    readonly property bool ready: converted ? sceneLoader.status === Loader3D.Ready && extent > 0.0001
                                            : loader.status === RuntimeLoader.Success

    // Габариты модели: у RuntimeLoader — свои, у balsam'овской сцены
    // собираем по всем её Model
    property vector3d lo: Qt.vector3d(0, 0, 0)
    property vector3d hi: Qt.vector3d(0, 0, 0)
    readonly property real extent: Math.max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 0)
    readonly property real k: root.modelSize / Math.max(extent, 0.0001)

    property var models: []         // все Model сцены — для габаритов
    property var timeline: null     // выбранная анимация

    function walk(obj, out) {
        if (!obj)
            return
        if (obj.bounds !== undefined && obj.skeleton !== undefined)
            out.push(obj)
        for (const c of obj.children ?? [])
            walk(c, out)
    }

    function measure() {
        const corners = []
        for (const m of models) {
            const a = m.bounds.minimum, b = m.bounds.maximum
            for (const x of [a.x, b.x]) for (const y of [a.y, b.y]) for (const z of [a.z, b.z])
                corners.push(m.mapPositionToNode(sceneLoader.item, Qt.vector3d(x, y, z)))
        }
        if (corners.length === 0)
            return
        lo = Qt.vector3d(Math.min(...corners.map(c => c.x)), Math.min(...corners.map(c => c.y)), Math.min(...corners.map(c => c.z)))
        hi = Qt.vector3d(Math.max(...corners.map(c => c.x)), Math.max(...corners.map(c => c.y)), Math.max(...corners.map(c => c.z)))
    }

    // Таймлайны balsam кладёт в resources корня сцены, имя анимации —
    // в objectName. Включаем только выбранный, остальные молчат
    function pickAnimation() {
        const item = sceneLoader.item
        if (!item)
            return
        const all = []
        for (const o of item.resources ?? [])
            if (o.currentFrame !== undefined && o.keyframeGroups !== undefined)
                all.push(o)
        let found = null
        for (const t of all) {
            t.enabled = t.objectName === root.animation
            if (t.enabled)
                found = t
        }
        if (root.animation !== "" && !found)
            console.warn("lock: в модели нет анимации", root.animation,
                         "— есть:", all.map(t => t.objectName).join(", ") || "никаких")
        timeline = found
    }
    onAnimationChanged: pickAnimation()

    // Анимация balsam'а считает кадры в миллисекундах (framesPerSecond: 1000)
    NumberAnimation {
        target: root.timeline
        property: "currentFrame"
        from: root.timeline?.startFrame ?? 0
        to: root.timeline?.endFrame ?? 0
        duration: root.timeline
            ? (to - from) / (root.timeline.framesPerSecond ?? 1000) * 1000 / Math.max(root.animationSpeed, 0.01)
            : 0
        loops: Animation.Infinite
        running: root.timeline !== null && duration > 0
    }

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
                duration: root.spinMs
                loops: Animation.Infinite
                running: root.spinMs > 0
            }

            // Любую модель вписываем в один размер и ставим центром в начало
            // координат: тогда она крутится вокруг себя, а не по орбите
            Node {
                scale: Qt.vector3d(root.k, root.k, root.k)
                position: Qt.vector3d(-(root.lo.x + root.hi.x) / 2 * root.k,
                                      -(root.lo.y + root.hi.y) / 2 * root.k,
                                      -(root.lo.z + root.hi.z) / 2 * root.k)

                RuntimeLoader {
                    id: loader
                    source: root.converted ? "" : root.model
                    // Молча падает, если Qt не видит плагин assetimporters
                    // (lib/qt-6/plugins из qtquick3d должен быть в QT_PLUGIN_PATH)
                    onStatusChanged: {
                        if (status === RuntimeLoader.Error)
                            console.warn("lock: модель", source, "не открылась:", errorString)
                    }
                    onBoundsChanged: {
                        if (!root.converted) {
                            root.lo = bounds.minimum
                            root.hi = bounds.maximum
                        }
                    }
                }

                Loader3D {
                    id: sceneLoader
                    source: root.scene
                    onLoaded: {
                        const out = []
                        root.walk(item, out)
                        root.models = out
                        for (const m of out)
                            m.boundsChanged.connect(root.measure)
                        root.measure()
                        root.pickAnimation()
                    }
                    onStatusChanged: {
                        if (status === Loader3D.Error)
                            console.warn("lock: сцена", source, "не открылась — нет модуля QtQuick.Timeline? Беру модель без анимаций")
                    }
                }
            }
        }

        layer.enabled: true
        layer.effect: ShaderEffect {
            fragmentShader: "../assets/shaders/dither.frag.qsb"
            property vector2d size: Qt.vector2d(width, height)
            property real pixel: Dither.avatarPixel
            property color c0: Dither.avatarDark
            property color c1: Dither.avatarMid
            property color c2: Dither.avatarLight
            property color c3: Dither.avatarBright
        }
    }
}
