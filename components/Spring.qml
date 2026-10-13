import QtQuick
import "../config"

// Пружина в духе MD3 Expressive — вместо кривой с длительностью.
// bouncy: лёгкий перелёт (~5%) и успокоение за ~0.3 с — для появления и
// движения; без него — быстро и без перелёта (закрытие, прокрутка).
// Для маленьких величин (scale) уменьшай epsilon, иначе пружина
// остановится раньше времени.
SpringAnimation {
    property bool bouncy: true
    spring: bouncy ? Motion.bouncySpring : Motion.calmSpring
    damping: bouncy ? Motion.bouncyDamping : Motion.calmDamping
    epsilon: 0.25
}
