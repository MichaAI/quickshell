pragma Singleton
import QtQuick

QtObject {
    // ===== Catppuccin Mocha =====
    readonly property color rosewater: "#f5e0dc"
    readonly property color flamingo: "#f2cdcd"
    readonly property color pink: "#f5c2e7"
    readonly property color mauve: "#cba6f7"
    readonly property color red: "#f38ba8"
    readonly property color maroon: "#eba0ac"
    readonly property color peach: "#fab387"
    readonly property color yellow: "#f9e2af"
    readonly property color green: "#a6e3a1"
    readonly property color teal: "#94e2d5"
    readonly property color sky: "#89dceb"
    readonly property color sapphire: "#74c7ec"
    readonly property color blue: "#89b4fa"
    readonly property color lavender: "#b4befe"
    readonly property color text: "#cdd6f4"
    readonly property color subtext1: "#bac2de"
    readonly property color subtext0: "#a6adc8"
    readonly property color overlay2: "#9399b2"
    readonly property color overlay1: "#7f849c"
    readonly property color overlay0: "#6c7086"
    readonly property color surface2: "#585b70"
    readonly property color surface1: "#45475a"
    readonly property color surface0: "#313244"
    readonly property color base: "#1e1e2e"
    readonly property color mantle: "#181825"
    readonly property color crust: "#11111b"

    // ===== Роли =====
    readonly property color barBg: crust        // бар, попауты, углы экрана
    readonly property color pillBg: base        // "таблетки" на баре
    readonly property color pillHover: surface0
    readonly property color popoutBg: crust
    readonly property color cardBg: base        // карточки внутри попаутов
    readonly property color accent: mauve

    // Градиент для "интересных штук"
    readonly property color gradStart: "#f38ba8"
    readonly property color gradEnd: "#cba6f7"

    readonly property string font: "JetBrainsMono Nerd Font"
    // Дисплейный шрифт для заголовков и крупных цифр, грузится из assets.
    // Мельче ~15px читается плохо — для обычного текста только `font`.
    readonly property string displayFont: neofolia.status === FontLoader.Ready ? neofolia.name : "Neofolia"
    readonly property FontLoader neofolia: FontLoader {
        source: Qt.resolvedUrl("assets/fonts/Neofolia-Regular.ttf")
    }
    readonly property int fontSize: 13

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
    }

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }
}
