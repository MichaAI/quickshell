pragma ComponentBehavior: Bound
import QtQuick
import "../config"

// Линейный прогресс MD3 Expressive (LinearProgressIndicator): активная
// часть и дорожка — отдельные скруглённые отрезки с зазором между ними,
// в конце дорожки точка-стоп. Градиент темы.
//   value  — доля 0…1; меньше нуля — «сколько всего, неизвестно»: два
//            бегущих отрезка, тайминги как в Compose (1750 мс);
//   target — куда значение сейчас поменяется (NaN — никуда). Разница
//            рисуется отдельным отрезком: прибавка — полупрозрачной
//            заливкой, убыль — контуром.
Item {
    id: root

    property real value: 0
    property real target: NaN
    property real gap: 4
    property color from: Theme.gradStart
    property color to: Theme.gradEnd
    property color trackColor: Theme.surface0

    implicitHeight: 4
    implicitWidth: 160

    readonly property bool indeterminate: value < 0
    readonly property bool hasTarget: !indeterminate && !isNaN(target)
        && Math.abs(target - value) > 0.001

    function clamp01(v) { return Math.max(0, Math.min(1, v)) }

    // Определённый: lo — до куда сплошная заливка, hi — конец разницы
    property real lo: clamp01(hasTarget ? Math.min(value, target) : value)
    property real hi: clamp01(hasTarget ? Math.max(value, target) : value)
    Behavior on lo { enabled: !root.indeterminate; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on hi { enabled: !root.indeterminate; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    readonly property bool growing: hasTarget && target > value

    // Неопределённый: t — мс от начала цикла
    property real t: 0
    NumberAnimation on t {
        running: root.visible && root.indeterminate
        loops: Animation.Infinite
        from: 0
        to: 1750
        duration: 1750
    }
    // Кусок кривой (0.2, 0, 0.8, 1) между start и end мс → 0…1
    function phase(start, end) {
        const x = Math.max(0, Math.min(1, (t - start) / (end - start)))
        return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2
    }

    // Отрезки слева направо: { x, w, kind }; дорожка заполняет промежутки
    // между остальными с зазором gap
    readonly property var segs: {
        const W = width
        const parts = []
        if (indeterminate) {
            parts.push({ a: phase(900, 1750) * W, b: phase(650, 1500) * W, kind: "active" })
            parts.push({ a: phase(250, 1250) * W, b: phase(0, 1000) * W, kind: "active" })
        } else {
            parts.push({ a: 0, b: lo * W, kind: "active" })
            parts.push({ a: lo * W, b: hi * W, kind: growing ? "up" : "down" })
        }
        const out = []
        let cursor = 0
        for (const p of parts) {
            const a = Math.max(p.a, cursor)
            if (p.b - a < 0.5) continue
            if (a - gap - cursor > 0.5)
                out.push({ x: cursor, w: a - gap - cursor, kind: "track" })
            out.push({ x: a, w: p.b - a, kind: p.kind })
            cursor = p.b + gap
        }
        if (W - cursor > 0.5)
            out.push({ x: cursor, w: W - cursor, kind: "track" })
        return out
    }

    Repeater {
        model: 5

        Rectangle {
            required property int index
            readonly property var s: root.segs[index] ?? null
            visible: s !== null
            x: s?.x ?? 0
            width: s?.w ?? 0
            height: root.height
            radius: height / 2
            color: s?.kind === "track" ? root.trackColor
                 : s?.kind === "up" ? Theme.alpha(root.to, 0.4)
                 : s?.kind === "down" ? "transparent" : root.to
            border.width: s?.kind === "down" ? 1 : 0
            border.color: Theme.alpha(root.to, 0.7)
            gradient: s?.kind === "active" ? grad : null
            OkGradient {
                id: grad
                orientation: Gradient.Horizontal
                from: root.from
                to: root.to
            }
        }
    }

    // Стоп в конце дорожки — пока до него не дошла заливка
    Rectangle {
        readonly property var last: root.segs[root.segs.length - 1] ?? null
        visible: !root.indeterminate && last !== null && last.kind === "track"
            && last.x < root.width - root.height * 2
        x: root.width - width
        width: root.height
        height: root.height
        radius: height / 2
        color: root.to
    }
}
