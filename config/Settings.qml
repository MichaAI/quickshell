pragma Singleton
import QtQuick

QtObject {
    readonly property int barHeight: 34
    readonly property int pillHeight: 26
    readonly property int pillRadius: 9
    readonly property int pillPadding: 10
    readonly property int barSpacing: 6

    readonly property int screenRadius: 14   // внутренние углы к краям монитора
    readonly property int popoutRadius: 16
    readonly property int popoutWing: 14     // радиус "крыльев" попаута к бару
    readonly property int popoutMaxHeight: 480

    // Терминал для `>` + Shift+Enter: дальше дописывается команда.
    // foot/kitty/wezterm start — как есть, alacritty/ghostty — с "-e".
    readonly property var terminal: ["kitty"]

    // ===== Погода (Open-Meteo) =====
    // Город для прогноза, например "Москва"; "" — определить по IP
    readonly property string weatherLocation: ""
    readonly property int weatherRefreshMin: 20

    // ===== Свет обложки (из попаута музыки на весь шелл) =====
    readonly property int glowBlur: 64          // радиус размытия, px
    readonly property real glowScale: 1.3       // во сколько раз свет больше обложки
    readonly property real glowSaturation: 0.4
    readonly property real glowBrightness: 0.1

    // ===== Экран блокировки =====
    // Обои на фоне; "" — градиент темы. ~ раскрывается в домашнюю папку
    readonly property string lockWallpaper: ""
    readonly property int lockWallpaperBlur: 48     // радиус размытия, 0 — без размытия
    readonly property real lockWallpaperDim: 0.45   // затемнение под плитки, 0…1
    readonly property int lockGap: 12
    readonly property int lockColumn: 340       // ширина колонки; 3D-ава — квадрат этой ширины
    readonly property int lockClockHeight: 200
    readonly property int lockMusicHeight: 100
    readonly property real lockModelSize: 190   // в него вписывается модель ~/avatar.*
    readonly property int lockSpinMs: 14000     // полный оборот модели, 0 — не крутить
    // Анимация модели по имени; "" — стоять. Список пишется в лог при
    // старте (нужен balsam из qtquick3d и модуль QtQuick.Timeline)
    readonly property string lockAnimation: ""
    readonly property real lockAnimationSpeed: 1  // 1 — как в модели
}
