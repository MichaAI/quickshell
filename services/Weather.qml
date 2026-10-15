pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// Погода из трёх источников без ключей: met.no, Open-Meteo и wttr.in.
// Каждый приводится к одному виду (погода — коды WMO, ветер — м/с).
// Источник, прокси и место — из Settings, а где там пусто — из переменных
// QS_WEATHER_* (их ставит модуль home-manager). Место: город, "широта,долгота"
// или пусто — город по IP. Запросы — curl: у него таймаут и прокси.
// Последний прогноз лежит на диске, пилюля появляется сразу при старте.
Singleton {
    id: root

    function pick(setting, env, fallback) {
        return setting || (Quickshell.env(env) ?? "") || fallback
    }

    readonly property string provider: pick(Settings.weatherProvider, "QS_WEATHER_PROVIDER", "metno")
    readonly property string proxy: pick(Settings.weatherProxy, "QS_WEATHER_PROXY", "")
    readonly property string location: pick(Settings.weatherLocation, "QS_WEATHER_LOCATION", "")
    readonly property var providers: ["metno", "openmeteo", "wttr"]

    readonly property string cacheFile: Quickshell.env("HOME") + "/.cache/quickshell-weather.json"
    readonly property string userAgent: "quickshell-weather github.com/MichaAI/quickshell"

    property bool ready: false
    property string place: ""
    property real lat: NaN
    property real lon: NaN

    // Сейчас
    property real temp: 0
    property real feels: 0
    property int humidity: 0
    property real wind: 0          // м/с
    property int windDir: 0        // откуда дует, градусы
    property int code: 0           // WMO
    property bool isDay: true
    property real todayMax: 0
    property real todayMin: 0
    property real uv: 0
    property string sunrise: ""    // HH:mm
    property string sunset: ""

    // [{ ts, time: "14", temp, code, isDay, pop, mm }] — сутки вперёд.
    // pop — вероятность осадков в %, -1 — источник её не даёт (тогда mm)
    property var hourly: []
    // [{ ts, name: "Пн", min, max, code, pop, mm }] — до 7 дней
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
        if ((c >= 61 && c <= 69) || (c >= 80 && c <= 82)) return "rain"
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
        case "rain": return c === 65 || c === 82 ? "󰖖" : (c >= 66 && c <= 69 ? "󰙿" : "󰖗")
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
            68: "Небольшой мокрый снег", 69: "Мокрый снег",
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

    // Подпись осадков: вероятность, а если её нет — миллиметры
    function rainText(pop, mm) {
        if (pop >= 0)
            return pop >= 20 ? pop + "%" : ""
        if (mm < 0.1)
            return ""
        return (mm < 10 ? mm.toFixed(1) : Math.round(mm)) + "мм"
    }

    // ===== Загрузка =====

    Component {
        id: fetcher
        Process {
            id: req
            property var done
            stdout: StdioCollector {
                onStreamFinished: {
                    let r = null
                    try {
                        r = JSON.parse(text)
                    } catch (e) {}
                    req.done(r)
                    req.destroy()
                }
            }
        }
    }

    // GET → JSON или null (сеть, таймаут, HTTP-ошибка, мусор)
    function get(url, done) {
        const cmd = ["curl", "-sfL", "-m", "20", "-A", userAgent]
        if (proxy !== "")
            cmd.push("-x", proxy)
        cmd.push(url)
        const p = fetcher.createObject(root, { command: cmd, done: done })
        p.running = true
    }

    function failed(what) {
        console.warn("weather: " + what + " (" + provider + (proxy !== "" ? ", прокси " + proxy : "") + ")")
        retry.restart()
    }

    function refresh() {
        if (!providers.includes(provider)) {
            console.warn("weather: неизвестный источник " + provider + ", есть " + providers.join(", "))
            return
        }
        if (!isNaN(lat)) {
            fetchForecast()
            return
        }
        const name = location.trim()
        const coords = name.match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/)
        if (coords) {
            lat = Number(coords[1])
            lon = Number(coords[2])
            fetchForecast()
        } else if (name !== "") {
            get("https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&accept-language=ru&q=" + encodeURIComponent(name), r => {
                if (!r) {
                    root.failed("не достучался до геокодера")
                    return
                }
                const p = r[0]
                if (!p) {
                    console.warn("weather: не нашёл место " + name)
                    return
                }
                if (root.place === "")
                    root.place = p.name
                root.lat = Number(p.lat)
                root.lon = Number(p.lon)
                root.fetchForecast()
            })
        } else {
            get("http://ip-api.com/json/?lang=ru&fields=status,city,lat,lon", r => {
                if (r?.status !== "success") {
                    root.failed("не определил город по IP")
                    return
                }
                if (root.place === "")
                    root.place = r.city
                root.lat = r.lat
                root.lon = r.lon
                root.fetchForecast()
            })
        }
    }

    // met.no просит не больше 4 знаков после запятой
    function coord(v) {
        return Number(v).toFixed(4)
    }

    function fetchForecast() {
        const la = coord(lat), lo = coord(lon)
        if (provider === "openmeteo") {
            get("https://api.open-meteo.com/v1/forecast?latitude=" + la + "&longitude=" + lo
                + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day"
                + "&hourly=temperature_2m,weather_code,precipitation_probability,precipitation,is_day"
                + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset,uv_index_max"
                + "&wind_speed_unit=ms&timezone=auto&forecast_days=7", r => {
                    if (r?.current) root.apply(root.fromOpenMeteo(r))
                    else root.failed("Open-Meteo не ответил")
                })
        } else if (provider === "wttr") {
            get("https://wttr.in/" + la + "," + lo + "?format=j1&lang=ru", r => {
                if (r?.current_condition) root.apply(root.fromWttr(r))
                else root.failed("wttr.in не ответил")
            })
        } else {
            get("https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=" + la + "&lon=" + lo, r => {
                if (!r?.properties?.timeseries) {
                    root.failed("met.no не ответил")
                    return
                }
                // Восход и закат — отдельно; без них день и ночь — по часам
                const off = -new Date().getTimezoneOffset()
                const pad = v => (v < 10 ? "0" : "") + v
                const tz = (off < 0 ? "-" : "+") + pad(Math.floor(Math.abs(off) / 60)) + ":" + pad(Math.abs(off) % 60)
                root.get("https://api.met.no/weatherapi/sunrise/3.0/sun?lat=" + la + "&lon=" + lo + "&offset=" + encodeURIComponent(tz),
                    sun => root.apply(root.fromMetno(r, sun)))
            })
        }
    }

    // ===== Источники → общий вид =====

    readonly property var dayNames: ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]

    function hhmm(s) {
        const m = (s ?? "").match(/(\d{1,2}):(\d{2})\s*(AM|PM)?/i)
        if (!m)
            return ""
        let h = Number(m[1]) % (m[3] ? 12 : 24)
        if (m[3] && m[3].toUpperCase() === "PM")
            h += 12
        return (h < 10 ? "0" : "") + h + ":" + m[2]
    }

    // День или ночь по часам восхода и заката, если источник не сказал сам
    function dayAt(date, rise, set) {
        const m = date.getHours() * 60 + date.getMinutes()
        const toMin = s => s ? Number(s.slice(0, 2)) * 60 + Number(s.slice(3, 5)) : NaN
        const r = toMin(rise), s = toMin(set)
        if (isNaN(r) || isNaN(s))
            return date.getHours() >= 7 && date.getHours() < 19
        return m >= r && m < s
    }

    // "YYYY-MM-DDTHH:mm" местного времени точки → Date
    function localDate(s) {
        const [d, t] = s.split("T")
        const [y, mo, dd] = d.split("-").map(Number)
        const [h, mi] = (t ?? "00:00").split(":").map(Number)
        return new Date(y, mo - 1, dd, h, mi)
    }

    function fromOpenMeteo(r) {
        const c = r.current, h = r.hourly, d = r.daily
        const nowKey = c.time.slice(0, 13)
        const start = Math.max(0, h.time.findIndex(t => t.slice(0, 13) === nowKey))
        const hours = []
        for (let i = start; i < Math.min(start + 24, h.time.length); i++)
            hours.push({
                ts: localDate(h.time[i]).getTime(),
                temp: h.temperature_2m[i],
                code: h.weather_code[i],
                isDay: h.is_day[i] === 1,
                pop: h.precipitation_probability[i] ?? -1,
                mm: h.precipitation[i] ?? 0
            })
        const days = d.time.map((t, i) => ({
            ts: localDate(t).getTime(),
            min: d.temperature_2m_min[i],
            max: d.temperature_2m_max[i],
            code: d.weather_code[i],
            pop: d.precipitation_probability_max[i] ?? -1,
            mm: d.precipitation_sum[i] ?? 0
        }))
        return {
            temp: c.temperature_2m, feels: c.apparent_temperature, humidity: c.relative_humidity_2m,
            wind: c.wind_speed_10m, windDir: c.wind_direction_10m, code: c.weather_code, isDay: c.is_day === 1,
            uv: d.uv_index_max[0] ?? 0, sunrise: d.sunrise[0].slice(11, 16), sunset: d.sunset[0].slice(11, 16),
            hourly: hours, daily: days
        }
    }

    // Символы met.no: "lightrainshowers_day", "cloudy", "heavysnowandthunder"…
    function metnoCode(sym) {
        const s = (sym ?? "cloudy").replace(/_(day|night|polartwilight)$/, "")
        if (s.includes("thunder")) return 95
        const heavy = s.startsWith("heavy"), light = s.startsWith("light")
        const showers = s.includes("showers")
        if (s.includes("sleet")) return light ? 68 : 69
        if (s.includes("snow")) return showers ? (heavy ? 86 : 85) : (heavy ? 75 : light ? 71 : 73)
        if (s.includes("rain")) return showers ? (heavy ? 82 : light ? 80 : 81) : (heavy ? 65 : light ? 61 : 63)
        return { clearsky: 0, fair: 1, partlycloudy: 2, cloudy: 3, fog: 45 }[s] ?? 3
    }

    function fromMetno(r, sun) {
        const ts = r.properties.timeseries
        const rise = sun?.properties?.sunrise?.time?.slice(11, 16) ?? ""
        const set = sun?.properties?.sunset?.time?.slice(11, 16) ?? ""
        const symOf = e => e.data.next_1_hours?.summary?.symbol_code ?? e.data.next_6_hours?.summary?.symbol_code
        const isDayOf = (e, date) => {
            const s = symOf(e) ?? ""
            if (s.endsWith("_day")) return true
            if (s.endsWith("_night") || s.endsWith("_polartwilight")) return false
            return root.dayAt(date, rise, set)
        }

        const hours = []
        for (const e of ts.slice(0, 24)) {
            const date = new Date(e.time)
            hours.push({
                ts: date.getTime(),
                temp: e.data.instant.details.air_temperature,
                code: metnoCode(symOf(e)),
                isDay: isDayOf(e, date),
                pop: -1,
                mm: e.data.next_1_hours?.details?.precipitation_amount ?? 0
            })
        }

        // Дни — по местной дате: мин/макс по всем точкам, осадки — сумма по
        // интервалам между точками, погода — на интервал около полудня
        const days = []
        for (let i = 0; i < ts.length; i++) {
            const e = ts[i], date = new Date(e.time)
            const key = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
            let day = days.find(x => x.ts === key)
            if (!day) {
                if (days.length === 7)
                    break
                day = { ts: key, min: Infinity, max: -Infinity, code: 3, noon: Infinity, pop: -1, mm: 0 }
                days.push(day)
            }
            const det = e.data.instant.details
            const n6 = e.data.next_6_hours?.details
            day.min = Math.min(day.min, det.air_temperature, n6?.air_temperature_min ?? Infinity)
            day.max = Math.max(day.max, det.air_temperature, n6?.air_temperature_max ?? -Infinity)
            const step = i + 1 < ts.length ? (new Date(ts[i + 1].time) - date) / 3600000 : 0
            if (step === 1)
                day.mm += e.data.next_1_hours?.details?.precipitation_amount ?? 0
            else if (step > 0)
                day.mm += (n6?.precipitation_amount ?? 0) * Math.min(1, step / 6)
            const sym = e.data.next_6_hours?.summary?.symbol_code ?? symOf(e)
            const dist = Math.abs(date.getHours() + (e.data.next_6_hours ? 3 : 0) - 12)
            if (sym && dist < day.noon) {
                day.noon = dist
                day.code = metnoCode(sym)
            }
        }
        for (const day of days)
            delete day.noon

        const now = ts[0], det = now.data.instant.details
        const todayKey = days[0]?.ts
        const uv = Math.max(0, ...ts.filter(e => {
            const d = new Date(e.time)
            return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() === todayKey
        }).map(e => e.data.instant.details.ultraviolet_index_clear_sky ?? 0))
        return {
            temp: det.air_temperature, feels: det.apparent_air_temperature ?? det.air_temperature,
            humidity: Math.round(det.relative_humidity), wind: det.wind_speed, windDir: det.wind_from_direction,
            code: metnoCode(symOf(now)), isDay: isDayOf(now, new Date()), uv: uv,
            sunrise: rise, sunset: set, hourly: hours, daily: days
        }
    }

    // Коды WorldWeatherOnline, которые отдаёт wttr.in, → WMO
    function wwoCode(c) {
        return ({
            113: 0, 116: 2, 119: 3, 122: 3, 143: 45, 248: 45, 260: 45,
            176: 80, 179: 85, 182: 68, 185: 56, 200: 95, 227: 73, 230: 75,
            263: 51, 266: 53, 281: 56, 284: 57, 293: 61, 296: 61, 299: 63, 302: 63,
            305: 65, 308: 65, 311: 66, 314: 67, 317: 68, 320: 69, 323: 71, 326: 71,
            329: 73, 332: 73, 335: 75, 338: 75, 350: 77, 353: 80, 356: 81, 359: 82,
            362: 68, 365: 69, 368: 85, 371: 86, 374: 77, 377: 77,
            386: 95, 389: 95, 392: 95, 395: 95
        })[Number(c)] ?? 3
    }

    function fromWttr(r) {
        const c = r.current_condition[0]
        const now = Date.now()
        const astro = w => w.astronomy?.[0] ?? {}
        const hours = []
        for (const w of r.weather) {
            const [y, mo, dd] = w.date.split("-").map(Number)
            for (const h of w.hourly) {
                const t = Number(h.time)
                const date = new Date(y, mo - 1, dd, Math.floor(t / 100), t % 100)
                // Точки — раз в 3 часа: берём ту, в чей интервал попадаем сейчас
                if (date.getTime() + 3 * 3600000 <= now || hours.length >= 9)
                    continue
                hours.push({
                    ts: date.getTime(),
                    temp: Number(h.tempC),
                    code: wwoCode(h.weatherCode),
                    isDay: dayAt(date, hhmm(astro(w).sunrise), hhmm(astro(w).sunset)),
                    pop: Math.max(Number(h.chanceofrain), Number(h.chanceofsnow)),
                    mm: Number(h.precipMM)
                })
            }
        }
        const days = r.weather.map(w => {
            const [y, mo, dd] = w.date.split("-").map(Number)
            // Погода дня — около полудня
            const noon = w.hourly.find(h => h.time === "1200") ?? w.hourly[0]
            return {
                ts: new Date(y, mo - 1, dd).getTime(),
                min: Number(w.mintempC),
                max: Number(w.maxtempC),
                code: wwoCode(noon.weatherCode),
                pop: Math.max(...w.hourly.map(h => Math.max(Number(h.chanceofrain), Number(h.chanceofsnow)))),
                mm: w.hourly.reduce((s, h) => s + Number(h.precipMM), 0)
            }
        })
        const today = r.weather[0]
        const rise = hhmm(astro(today).sunrise), set = hhmm(astro(today).sunset)
        if (place === "")
            place = r.nearest_area?.[0]?.areaName?.[0]?.value ?? ""
        return {
            temp: Number(c.temp_C), feels: Number(c.FeelsLikeC), humidity: Number(c.humidity),
            wind: Number(c.windspeedKmph) / 3.6, windDir: Number(c.winddirDegree), code: wwoCode(c.weatherCode),
            isDay: dayAt(new Date(), rise, set), uv: Number(c.uvIndex),
            sunrise: rise, sunset: set, hourly: hours, daily: days
        }
    }

    // ===== Применение и кеш =====

    // Подписи часов и дней — от текущего момента: прошедшее выкидываем
    function relabel(hours, days) {
        const now = Date.now()
        const step = hours.length > 1 ? hours[1].ts - hours[0].ts : 3600000
        hours = hours.filter(h => h.ts + step > now)
        hours.forEach((h, i) => h.time = i === 0 ? "Сейч" : String(new Date(h.ts).getHours()).padStart(2, "0"))
        const d = new Date(now)
        const today = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        days = days.filter(x => x.ts >= today)
        days.forEach(x => x.name = x.ts === today ? "Сегодня" : root.dayNames[new Date(x.ts).getDay()])
        return [hours, days]
    }

    function apply(w, fromCache) {
        const [hours, days] = relabel(w.hourly, w.daily)
        if (days.length === 0)
            return
        temp = w.temp
        feels = w.feels
        humidity = w.humidity
        wind = w.wind
        windDir = w.windDir
        code = w.code
        isDay = w.isDay
        uv = w.uv
        sunrise = w.sunrise
        sunset = w.sunset
        hourly = hours
        daily = days
        todayMax = days[0].max
        todayMin = days[0].min
        ready = true
        if (!fromCache)
            cache.setText(JSON.stringify(Object.assign({ place: place, provider: provider, location: location, saved: Date.now() }, w)) + "\n")
    }

    // Кеш — только для того же места и источника и не старше суток
    FileView {
        id: cache
        path: root.cacheFile
        printErrors: false
        onLoaded: {
            try {
                const w = JSON.parse(text())
                if (root.ready || w.provider !== root.provider || w.location !== root.location
                        || Date.now() - w.saved > 24 * 3600000)
                    return
                if (root.place === "")
                    root.place = w.place ?? ""
                root.apply(w, true)
            } catch (e) {}
        }
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
