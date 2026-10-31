import QtQuick
import "Match.js" as Match

// «?» — поиск режимов: ⏎ ставит префикс в строку и переключает режим
Item {
    id: mode

    required property var launcher

    // prefix — что вписать; run — для того, что открывается не префиксом
    readonly property var catalog: [
        { id: "apps", prefix: "", title: "Приложения", keys: "apps launch запуск", how: "просто печатай   ·   Tab — действия приложения" },
        { id: "calc", prefix: "=", title: "Калькулятор", keys: "calc qalc math units график plot", how: "= 2^10   ·   = 10 km to mi   ·   = plot(sin(x))" },
        { id: "vars", prefix: "$", title: "Переменные калькулятора", keys: "vars variables", how: "$" },
        { id: "shell", prefix: ">", title: "Команда zsh", keys: "shell terminal run командная", how: "> команда   ·   ⇧⏎ в терминале" },
        { id: "windows", prefix: ":", title: "Окна", keys: "windows switch переключить", how: ": заголовок" },
        { id: "actions", prefix: "!", title: "Действия", keys: "power actions питание скриншот сон выключить", how: "! сон, ! скриншот…" },
        { id: "clip", prefix: "#", title: "Буфер обмена", keys: "clipboard cliphist история буфера цвет color", how: "# текст   ·   #rrggbb — цвет" },
        { id: "files", prefix: "~", title: "Поиск файлов", keys: "files fd find найти", how: "~ имя" },
        { id: "path", prefix: "~/", title: "Обзор по пути", keys: "path browse папка directory", how: "~/ или /" },
        { id: "glyphs", prefix: ";", title: "Эмодзи и иконки", keys: "emoji nerd icons смайлы глифы", how: "; кот, ; heart" },
        { id: "kill", prefix: "kill ", title: "Процессы", keys: "kill processes ps убить", how: "kill имя   ·   ⇧⏎ KILL" },
        { id: "ports", prefix: "port ", title: "Занятые порты", keys: "ports ss listen сеть network сокеты", how: "port 8080   ·   ⇧Del — TERM процессу" },
        { id: "docker", prefix: "docker ", title: "Docker", keys: "docker containers контейнеры compose", how: "docker имя   ·   Tab — действия" },
        { id: "kube", prefix: "kube ", title: "Kubernetes", keys: "kube k8s kubectl pods поды кластер", how: "kube под   ·   kube @ — контексты" },
        { id: "nix", prefix: ",", title: "Запуск через nix", keys: "nix comma run без установки nixpkgs", how: ",cowsay привет   ·   ⇧⏎ в терминале" },
        { id: "translate", prefix: "tr ", title: "Переводчик", keys: "translate перевод google язык", how: "tr hello   ·   tr de: привет" },
        { id: "gif", prefix: "gif ", title: "Гифки", keys: "gif gifs klipy giphy анимация", how: "gif кот   ·   ⇧⏎ копировать саму гифку" },
        { id: "qr", prefix: "qr ", title: "QR-код", keys: "qr qrcode код ссылка", how: "qr текст   ·   пусто — из буфера" },
        { id: "sys", topic: "vol", prefix: "vol ", title: "Громкость", keys: "volume звук громкость sound output выход sink", how: "vol 30   ·   vol +5   ·   vol mute   ·   выходы и приложения" },
        { id: "sys", topic: "mic", prefix: "mic ", title: "Микрофон", keys: "mic microphone микрофон input вход", how: "mic 50   ·   mic mute" },
        { id: "sys", topic: "br", prefix: "br ", title: "Яркость", keys: "brightness яркость экран backlight", how: "br 70   ·   br +10" },
        { id: "sys", topic: "bt", prefix: "bt ", title: "Bluetooth", keys: "bluetooth блютуз наушники", how: "bt имя   ·   bt on / off" },
        { id: "sys", topic: "wifi", prefix: "wifi ", title: "Wi-Fi", keys: "wifi wi-fi сеть network вайфай", how: "wifi сеть   ·   wifi сеть / пароль   ·   wifi off" },
        { id: "sys", topic: "media", prefix: "mp ", title: "Плеер", keys: "media player music плеер музыка next pause", how: "mp next   ·   mp pause" },
        { id: "history", title: "История запросов", keys: "history история ctrl+r", how: "Ctrl+R, ↑ в пустой строке",
          run: () => launcher.openHistory() },
        { id: "picker", title: "Выбор цвета", keys: "color picker colour колесо цвет", how: "! выбор цвета, rgb(…), #rrggbb",
          run: () => launcher.openPicker("") },
        { id: "modes", prefix: "?", title: "Режимы", keys: "modes help помощь", how: "этот список" }
    ]

    function items() {
        return Match.filterBy(catalog, launcher.arg.trim(), m => [m.title, m.prefix?.trim() ?? "", m.keys]).map(m => {
            const info = m.topic ? launcher.sysTopics[m.topic] : launcher.modes[m.id]
            return {
                glyph: info.icon,
                glyphColor: info.color,
                title: m.title,
                sub: m.how,
                badge: m.prefix !== undefined ? (m.prefix === "" ? "без префикса" : m.prefix.trim()) : "",
                ghostSource: m.title,
                run: () => {
                    if (m.run) m.run()
                    else launcher.setQuery(m.prefix)
                }
            }
        })
    }
}
