pragma Singleton
import Quickshell
import QtQuick
import "../config"

// Погода с Open-Meteo (без ключа). Место — Settings.weatherLocation
// или, если там пусто, город по IP.
Singleton {
    id: root

    property bool ready: false
    property string place: ""
    property real lat: NaN
    property real lon: NaN

    // Сейчас
    property real temp: 0
    property real feels: 0
    property int humidity: 0
    property real wind: 0          // км/ч
    property int windDir: 0        // откуда дует, градусы
    property int code: 0           // WMO
    property bool isDay: true
    property real todayMax: 0
    property real todayMin: 0
    property real uv: 0
    property string sunrise: ""    // HH:mm
    property string sunset: ""

    // [{ time: "14", temp, code, isDay, pop }] — 24 часа начиная с текущего
    property var hourly: []
    // [{ date: Date, name: "Пн", min, max, code, pop }] — 7 дней
    property var daily: []

    readonly property string kind: kindOf(code)
    readonly property string icon: iconOf(code, isDay)
    readonly property string description: textOf(code)

    // ===== WMO-коды =====

    function kindOf(c) {
        if (c === 0 || c === 1) return "clear"
        if (c === 2) return "partly"
        if (c === 3) return "cloudy"
        if (c === 45 || c === 48) return "fog"
        if (c >= 51 && c <= 57) return "drizzle"
        if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return "rain"
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return "snow"
        if (c >= 95) return "thunder"
        return "cloudy"
    }

    function iconOf(c, day) {
        switch (kindOf(c)) {
        case "clear": return day ? "󰖙" : "󰖔"
        case "partly": return day ? "󰖕" : "󰼱"
        case "cloudy": return "󰖐"
        case "fog": return "󰖑"
        case "drizzle": return "󰖗"
        case "rain": return c === 65 || c === 82 ? "󰖖" : (c === 66 || c === 67 ? "󰙿" : "󰖗")
        case "snow": return c === 75 || c === 86 ? "󰼶" : "󰖘"
        case "thunder": return c === 95 ? "󰖓" : "󰙾"
        }
        return "󰖐"
    }

    function colorOf(c, day) {
        switch (kindOf(c)) {
        case "clear": return day ? Theme.yellow : Theme.lavender
        case "partly": return day ? Theme.peach : Theme.lavender
        case "fog": return Theme.overlay2
        case "drizzle":
        case "rain": return Theme.sapphire
        case "snow": return Theme.sky
        case "thunder": return Theme.mauve
        }
        return Theme.subtext0
    }

    function textOf(c) {
        const names = {
            0: "Ясно", 1: "Преимущественно ясно", 2: "Переменная облачность", 3: "Пасмурно",
            45: "Туман", 48: "Изморозь",
            51: "Слабая морось", 53: "Морось", 55: "Сильная морось",
            56: "Ледяная морось", 57: "Ледяная морось",
            61: "Небольшой дождь", 63: "Дождь", 65: "Ливень",
            66: "Ледяной дождь", 67: "Ледяной дождь",
            71: "Небольшой снег", 73: "Снег", 75: "Снегопад", 77: "Снежная крупа",
            80: "Небольшой ливень", 81: "Ливень", 82: "Сильный ливень",
            85: "Снегопад", 86: "Сильный снегопад",
            95: "Гроза", 96: "Гроза с градом", 99: "Гроза с градом"
        }
        return names[c] ?? "—"
    }

    function fmt(t) {
        const r = Math.round(t)
        return (r > 0 ? "+" : "") + r + "°"
    }

    // ===== Загрузка =====

    function get(url, done, fail) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status === 200) {
                try {
                    done(JSON.parse(xhr.responseText))
                    return
                } catch (e) {}
            }
            fail?.()
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function failed() {
        retry.restart()
    }

    function refresh() {
        if (!isNaN(lat)) {
            fetchForecast()
            return
        }
        const name = Settings.weatherLocation.trim()
        if (name !== "") {
            get("https://geocoding-api.open-meteo.com/v1/search?count=1&language=ru&name=" + encodeURIComponent(name),
                r => {
                    const p = r.results?.[0]
                    if (!p) {
                        console.warn("weather: не нашёл место", name)
                        return
                    }
                    root.place = p.name
                    root.lat = p.latitude
                    root.lon = p.longitude
                    root.fetchForecast()
                }, failed)
        } else {
            get("http://ip-api.com/json/?lang=ru&fields=status,city,lat,lon", r => {
                if (r.status !== "success") {
                    root.failed()
                    return
                }
                root.place = r.city
                root.lat = r.lat
                root.lon = r.lon
                root.fetchForecast()
            }, failed)
        }
    }

    function fetchForecast() {
        get("https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day"
            + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"
            + "&timezone=auto&forecast_days=7", apply, failed)
    }

    // Время у Open-Meteo — местное для точки, строками "YYYY-MM-DDTHH:mm"
    function apply(r) {
        const c = r.current
        temp = c.temperature_2m
        feels = c.apparent_temperature
        humidity = c.relative_humidity_2m
        wind = c.wind_speed_10m
        windDir = c.wind_direction_10m
        code = c.weather_code
        isDay = c.is_day === 1

        const h = r.hourly
        const start = Math.max(0, h.time.findIndex(t => t.slice(0, 13) === c.time.slice(0, 13)))
        const hours = []
        for (let i = start; i < Math.min(start + 24, h.time.length); i++)
            hours.push({
                time: i === start ? "Сейч" : h.time[i].slice(11, 13),
                temp: h.temperature_2m[i],
                code: h.weather_code[i],
                isDay: h.is_day[i] === 1,
                pop: h.precipitation_probability[i] ?? 0
            })
        hourly = hours

        const d = r.daily
        const names = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
        const days = []
        for (let i = 0; i < d.time.length; i++) {
            const [y, m, dd] = d.time[i].split("-").map(Number)
            const date = new Date(y, m - 1, dd)
            days.push({
                name: i === 0 ? "Сегодня" : names[date.getDay()],
                min: d.temperature_2m_min[i],
                max: d.temperature_2m_max[i],
                code: d.weather_code[i],
                pop: d.precipitation_probability_max[i] ?? 0
            })
        }
        daily = days
        todayMax = d.temperature_2m_max[0]
        todayMin = d.temperature_2m_min[0]
        uv = d.uv_index_max[0] ?? 0
        sunrise = d.sunrise[0].slice(11, 16)
        sunset = d.sunset[0].slice(11, 16)
        ready = true
    }

    Component.onCompleted: refresh()

    Timer {
        interval: Settings.weatherRefreshMin * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: retry
        interval: 2 * 60 * 1000
        onTriggered: root.refresh()
    }
}
