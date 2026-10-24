pragma Singleton
import QtQuick

// Дизеринг и зерно: всё, что сознательно «пачкает» картинку.
QtObject {
    // ===== 3D-ава на экране блокировки =====
    // Крупный упорядоченный дизеринг (Байер 4×4): размер клетки в пикселях
    readonly property real avatarPixel: 4
    // Палитра от тёмного к светлому: яркость модели раскладывается
    // ровно на эти 4 цвета
    readonly property color avatarDark: Theme.surface1
    readonly property color avatarMid: Theme.mauve
    readonly property color avatarLight: Theme.pink
    readonly property color avatarBright: Theme.rosewater

    // ===== Зерно против полос в плавных градиентах =====
    // По свету обложки: шум ±N уровней из 255 по цвету и прозрачности
    readonly property real glowDither: 1.5
    // По фону экрана блокировки. Шум чёрно-белый, так что 0.01 — это
    // ±1–2 уровня яркости: полосы уходят, а зерна глазом не видно
    readonly property real lockNoise: 0.01
}
