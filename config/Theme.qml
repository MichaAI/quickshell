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
        source: Qt.resolvedUrl("../assets/fonts/Neofolia-Regular.ttf")
    }
    readonly property int fontSize: 13

    // Слайдер MD3E выбранного Settings.sliderSize (токены MDC Android
    // m3_comp_slider_*): [дорожка, внешние углы, ручка]
    readonly property var sliderSpec: ({
        xsmall: [16, 8, 44], small: [24, 8, 44], medium: [40, 12, 44],
        large: [56, 16, 68], xlarge: [96, 28, 108]
    })[Settings.sliderSize] ?? [16, 8, 44]

    // ===== OkLab =====
    // Смешивание в OkLab (Björn Ottosson): без провала в серую середину и
    // с ровной на глаз яркостью. Альфа премультиплицирована, как в CSS, —
    // переход в прозрачность не тащит за собой чёрный
    function mix(a, b, t) {
        // Строку "#rrggbb" — в цвет: у строки нет .r/.g/.b
        if (typeof a === "string") a = Qt.color(a)
        if (typeof b === "string") b = Qt.color(b)
        const p = oklab(a), q = oklab(b)
        const al = a.a + (b.a - a.a) * t
        if (al <= 0)
            return Qt.rgba(0, 0, 0, 0)
        const m = i => (p[i] * a.a + (q[i] * b.a - p[i] * a.a) * t) / al
        return fromOklab(m(0), m(1), m(2), al)
    }

    function oklab(c) {
        const r = _lin(c.r), g = _lin(c.g), b = _lin(c.b)
        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
    }

    function fromOklab(L, A, B, alpha) {
        const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        const s = Math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        return Qt.rgba(_srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                       _srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                       _srgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
                       alpha)
    }

    function _lin(x) {
        return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
    }

    function _srgb(x) {
        x = Math.max(0, Math.min(1, x))
        return x <= 0.0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - 0.055
    }

    // Стопы по OkLab в CanvasGradient — как OkGradient, 8 отрезков
    function okStops(grad, a, b) {
        for (let i = 0; i <= 8; i++)
            grad.addColorStop(i / 8, mix(a, b, i / 8))
        return grad
    }

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }
}
