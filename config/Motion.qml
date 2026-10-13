pragma Singleton
import QtQuick

// Пружины в духе MD3 Expressive (см. components/Spring.qml).
// spring — жёсткость (быстрее разгон), damping — затухание: чем меньше,
// тем сильнее перелёт и дольше колебания.
QtObject {
    // С лёгким перелётом (~5%), успокоение ~0.3 с — появление и движение
    readonly property real bouncySpring: 5
    readonly property real bouncyDamping: 0.35

    // Без перелёта — закрытие, прокрутка
    readonly property real calmSpring: 8
    readonly property real calmDamping: 0.6

    // Экран блокировки: подпрыгивание значка раскладки и тряска поля при ошибке
    readonly property real kickSpring: 6
    readonly property real kickDamping: 0.18
    readonly property real shakeSpring: 14
    readonly property real shakeDamping: 0.12
    readonly property real shakeDistance: 18
}
