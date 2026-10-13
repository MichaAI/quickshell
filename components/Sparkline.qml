import QtQuick
import "../config"

// Мини-график истории значений (0..1).
Canvas {
    id: root

    property var values: []
    property color color: Theme.mauve

    implicitWidth: 120
    implicitHeight: 28

    onValuesChanged: requestPaint()
    onColorChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const vals = values
        if (!vals || vals.length < 2)
            return

        const w = width, h = height
        const step = w / (vals.length - 1)

        ctx.beginPath()
        ctx.moveTo(0, h - Math.min(1, vals[0]) * (h - 2) - 1)
        for (let i = 1; i < vals.length; i++)
            ctx.lineTo(i * step, h - Math.min(1, vals[i]) * (h - 2) - 1)

        ctx.strokeStyle = root.color
        ctx.lineWidth = 1.5
        ctx.lineJoin = "round"
        ctx.stroke()

        ctx.lineTo(w, h)
        ctx.lineTo(0, h)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.15)
        ctx.fill()
    }
}
