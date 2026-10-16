import QtQuick
import "../config"

// Gradient from → to, посчитанный в OkLab (Theme.mix). Сам Qt тянет цвет
// между стопами только линейно по sRGB, поэтому стопов 9 (8 отрезков):
// на таких коротких кусках разница с честным OkLab ~0.0005 ΔE OK.
// start/end — где стоят from и to; за ними Qt держит крайний цвет
Gradient {
    id: root

    property color from
    property color to
    property real start: 0
    property real end: 1

    function at(i) { return root.start + (root.end - root.start) * i / 8 }
    function col(i) { return Theme.mix(root.from, root.to, i / 8) }

    GradientStop { position: root.at(0); color: root.col(0) }
    GradientStop { position: root.at(1); color: root.col(1) }
    GradientStop { position: root.at(2); color: root.col(2) }
    GradientStop { position: root.at(3); color: root.col(3) }
    GradientStop { position: root.at(4); color: root.col(4) }
    GradientStop { position: root.at(5); color: root.col(5) }
    GradientStop { position: root.at(6); color: root.col(6) }
    GradientStop { position: root.at(7); color: root.col(7) }
    GradientStop { position: root.at(8); color: root.col(8) }
}
