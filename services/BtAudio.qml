pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// Кодек Bluetooth-наушников и его качество — это PipeWire, а не budsd,
// так что работает с любыми наушниками. Ничего не зашито: кодеки — профили
// устройства (a2dp-sink-<кодек>), какие PipeWire предлагает; качество —
// свойство quality вывода с вариантами из его PropInfo (у LDAC — auto, hq,
// sq, mq), меняется на лету. Его PipeWire не помнит: выбранное храним по
// MAC и кодеку и ставим заново, как только вывод появляется
// (переподключение, смена кодека). Состояние читаем pw-dump'ом: при смене
// bluez-выводов и после своих команд — постоянно его не гоняем
Singleton {
    id: root

    // {mac, name, deviceId, nodeId, codec, profile, profiles: [{index, codec}],
    //  quality: {current, options: [{id, value}]} | null — у кодека не меняется}
    // или null — Bluetooth-вывода нет
    property var dev: null
    // "MAC/кодек" → id варианта качества
    property var saved: ({})

    readonly property var quality: dev?.quality ?? null

    // Выводы bluez: появились, пропали, пересоздались — перечитать
    readonly property string sinks: Pipewire.nodes.values // qmllint disable missing-property
        .filter(n => n.name.startsWith("bluez_output.")).map(n => n.id).join(",")
    onSinksChanged: refresh()

    function refresh() {
        // Сразу после смены профиля вывод ещё собирается — чуть подождём
        settle.restart()
    }

    Timer {
        id: settle
        interval: 300
        onTriggered: dump.running = true
    }

    Process {
        id: dump
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    function parse(text) {
        let all
        try {
            all = JSON.parse(text)
        } catch (e) {
            return
        }
        const props = o => o.info?.props ?? {}
        const node = all.find(o => o.type === "PipeWire:Interface:Node"
            && props(o)["media.class"] === "Audio/Sink" && props(o)["api.bluez5.address"])
        if (!node) {
            dev = null
            return
        }
        const p = props(node)
        const device = all.find(o => o.id === p["device.id"])
        const params = device?.info?.params ?? {}
        // Кодек — последнее слово описания: «…(приёмник A2DP, кодек LDAC)»
        const codecOf = pr => (pr.description.match(/(\S+)\)\s*$/)?.[1] ?? pr.name).toLowerCase().replace("-", "_")
        // Качество кодека: перечисление с подписями. Тот же ключ quality
        // у ресемплера — но у того имя resample.quality и диапазон, а не варианты
        const info = (node.info.params?.PropInfo ?? [])
            .find(x => x.id === "quality" && x.name === undefined && Array.isArray(x.labels))
        let quality = null
        if (info) {
            const options = []
            for (let i = 0; i + 1 < info.labels.length; i += 2)
                options.push({ id: String(info.labels[i + 1]), value: info.labels[i] })
            const v = (node.info.params?.Props ?? []).find(x => x.quality !== undefined)?.quality
            quality = { options: options, current: options.find(o => o.value === v)?.id ?? "" }
        }
        const mac = p["api.bluez5.address"]
        dev = {
            mac: mac,
            name: p["node.description"] ?? mac,
            deviceId: device?.id ?? -1,
            nodeId: node.id,
            codec: p["api.bluez5.codec"] ?? "",
            quality: quality,
            profile: params.Profile?.[0]?.index ?? -1,
            profiles: (params.EnumProfile ?? [])
                .filter(pr => pr.name.startsWith("a2dp-sink") && pr.available !== "no")
                .map(pr => ({ index: pr.index, codec: codecOf(pr) }))
                // «a2dp-sink» — лучший кодек, он же бывает и отдельным профилем
                .filter((pr, i, a) => a.findIndex(x => x.codec === pr.codec) === i)
        }
        // Запомненное качество — вывод мог только что появиться
        const want = saved[mac + "/" + dev.codec]
        if (quality && want && want !== quality.current && quality.options.some(o => o.id === want))
            applyQuality(want)
    }

    // ===== Управление =====

    function setCodec(index) {
        if (!dev || index === dev.profile)
            return
        Quickshell.execDetached(["wpctl", "set-profile", String(dev.deviceId), String(index)])
        refresh()
    }

    function setQuality(id) {
        if (!quality)
            return
        const s = Object.assign({}, saved)
        s[dev.mac + "/" + dev.codec] = id
        saved = s
        save()
        applyQuality(id)
    }

    function applyQuality(id) {
        const o = quality.options.find(x => x.id === id)
        if (!o)
            return
        dev = Object.assign({}, dev, { quality: Object.assign({}, quality, { current: id }) })
        Quickshell.execDetached(["pw-cli", "s", String(dev.nodeId), "Props",
            "{ quality: " + o.value + " }"])
    }

    // ===== Память =====

    readonly property string file: Quickshell.env("HOME") + "/.cache/quickshell-btaudio.json"

    function save() {
        view.setText(JSON.stringify({ quality: saved }) + "\n")
    }

    FileView {
        id: view
        path: root.file
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const v = JSON.parse(text())
                if (v && typeof v.quality === "object") root.saved = v.quality
            } catch (e) {}
        }
    }
}
