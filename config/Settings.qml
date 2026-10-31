pragma Singleton
import QtQuick

QtObject {
    readonly property int barHeight: 34
    readonly property int pillHeight: 26
    readonly property int pillRadius: 9
    readonly property int pillPadding: 10
    readonly property int barSpacing: 6

    // ===== Слайдеры: громкость, пипетка (прогресс музыки — всегда волна) =====
    // "expressive" — MD3 Expressive: дорожка из двух частей и ручка-палочка
    // с зазором; "pill" — пилюля в пилюле, как в шторке Android 12–15
    readonly property string sliderStyle: "expressive"
    // Толщина по шкале MD3E: "xsmall" 16 px, "small" 24, "medium" 40,
    // "large" 56, "xlarge" 96
    readonly property string sliderSize: "xsmall"

    // Попаут музыки красится в цвета обложки: оттенки из картинки, яркость
    // и насыщенность — как у темы. false — всегда цвета темы
    readonly property bool coverColors: true

    // Уведомления смахиваются двумя пальцами по тачпаду. Если карточка
    // едет против пальцев — true
    readonly property bool notifSwipeInvert: false
    // Уведомления одного приложения — стопкой в центре уведомлений:
    // видно последнее, клик по шапке раскрывает остальные
    readonly property bool notifGroups: false

    readonly property int screenRadius: 14   // внутренние углы к краям монитора
    readonly property int popoutRadius: 16
    readonly property int popoutWing: 14     // радиус "крыльев" попаута к бару
    readonly property int popoutMaxHeight: 480

    // Значки трея, которые прятать: подстрока id или заголовка, без
    // регистра. blueman — Bluetooth уже своей пилюлей
    readonly property var trayHidden: ["blueman"]

    // Терминал для `>` + Shift+Enter: дальше дописывается команда.
    // foot/kitty/wezterm start — как есть, alacritty/ghostty — с "-e".
    readonly property var terminal: ["kitty"]

    // ===== Погода (Open-Meteo) =====
    // Город для прогноза, например "Москва"; "" — из опции home-manager
    // weather.location, а без неё — по IP
    readonly property string weatherLocation: ""
    // Город можно и координатами: "56.13,47.25"
    // Источник: "metno" (met.no), "openmeteo" или "wttr" (wttr.in, 3 дня);
    // "" — из опции home-manager weather.provider, а без неё — metno
    readonly property string weatherProvider: ""
    // Прокси для запросов погоды, как у curl -x: "socks5h://127.0.0.1:1080",
    // "http://host:3128"; "" — из опции weather.proxy, а без неё — напрямую
    readonly property string weatherProxy: ""
    readonly property int weatherRefreshMin: 20

    // ===== Лончер: сетевые режимы =====
    // Гифки (gif …): "klipy" (ключ — partner.klipy.com) или "giphy"
    // (developers.giphy.com). Ключи бесплатные. Сюда ключ лучше не писать
    // (уйдёт в стор): «gif key <ключ>» в лаунчере сохранит его в файл,
    // а для sops/agenix есть опция home-manager gif.keyFile
    readonly property string gifProvider: "klipy"
    readonly property string gifKey: ""
    // Переводчик (tr …): с первого языка — на второй, с остальных — на первый
    readonly property var translateLangs: ["ru", "en"]
    // Прокси для гифок и переводчика, как у curl -x; "" — напрямую
    readonly property string netProxy: ""

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
