pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Наушники с управлением: клиент демона budsd (tools/budsd) по JSON-RPC.
// Демон сам видит подключённые наушники и шлёт, что они умеют (caps) и
// что в них сейчас (values, battery…). Модель шелл не знает — попаут
// рисует контролы из caps.
//
// Настройку меняем сразу, не дожидаясь наушников, а если они не
// подтвердили — откатываем к тому, что в них на самом деле, и шлём failed
Singleton {
    id: root

    // MAC → {device, name, status, message, caps, values, battery, devices, info}
    property var devices: ({})
    // Какие показывать, если подключено несколько
    property string selected: ""

    readonly property var list: Object.values(devices)
    readonly property var current: {
        const pick = list.find(d => d.device === selected)
        return pick ?? list.find(d => d.status === "ready") ?? list[0] ?? null
    }
    readonly property bool ready: current?.status === "ready"

    // id контрола и почему не вышло
    signal failed(string device, string id, string message)

    // ===== JSON-RPC =====

    property int nextId: 1
    property var pending: ({})

    function call(method, params, done) {
        if (!proc.running) {
            done?.({ code: 2, message: "budsd не запущен" }, null)
            return
        }
        const id = nextId++
        if (done)
            pending[id] = done
        proc.write(JSON.stringify({ jsonrpc: "2.0", id: id, method: method, params: params ?? {} }) + "\n")
    }

    function receive(line) {
        let msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            console.warn("buds: не JSON от budsd:", line)
            return
        }
        if (msg.id !== undefined && msg.method === undefined) {
            const done = pending[msg.id]
            delete pending[msg.id]
            done?.(msg.error ?? null, msg.result ?? null)
            return
        }
        const p = msg.params ?? {}
        const mac = p.device
        switch (msg.method) {
        case "device":
            if (p.status === "gone")
                drop(mac)
            else
                patch(mac, d => Object.assign(d, p))
            break
        case "value":
            patch(mac, d => d.values = Object.assign({}, d.values, { [p.id]: p.value }))
            break
        // Батарея — полный снимок: что не пришло (кейс убрали), того нет
        case "battery": {
            const b = Object.assign({}, p)
            delete b.device
            patch(mac, d => d.battery = b)
            break
        }
        case "info": {
            const add = Object.assign({}, p)
            delete add.device
            patch(mac, d => d.info = Object.assign({}, d.info, add))
            break
        }
        case "devices":
            patch(mac, d => d.devices = p.list)
            break
        }
    }

    // Поменять запись одних наушников: новый объект, чтобы ожили биндинги
    function patch(mac, fn) {
        if (!mac)
            return
        const d = Object.assign({ device: mac, values: {}, battery: {}, devices: [], info: {} }, devices[mac])
        fn(d)
        const all = Object.assign({}, devices)
        all[mac] = d
        devices = all
    }

    function drop(mac) {
        const all = Object.assign({}, devices)
        delete all[mac]
        devices = all
    }

    // ===== Управление =====

    function value(id) {
        return current?.values?.[id]
    }

    function set(id, v) {
        const d = current
        if (!d)
            return
        const before = d.values?.[id]
        patch(d.device, x => x.values = Object.assign({}, x.values, { [id]: v }))
        call("set", { device: d.device, id: id, value: v }, (err, res) => {
            if (!err)
                return
            const actual = err.data?.id === id && err.data.value !== null ? err.data.value : before
            patch(d.device, x => x.values = Object.assign({}, x.values, { [id]: actual }))
            root.failed(d.device, id, err.message)
        })
    }

    function act(name, params, done) {
        const d = current
        if (!d)
            return
        call(name, Object.assign({ device: d.device }, params ?? {}), (err, res) => {
            if (err)
                root.failed(d.device, name, err.message)
            done?.(err, res)
        })
    }

    // ===== Демон =====

    // Сколько раз подряд budsd падал сразу после запуска
    property int crashes: 0

    Process {
        id: proc
        command: ["budsd"]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => root.receive(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("buds:", line)
        }

        property bool started: false

        onStarted: {
            started = true
            alive.restart()
            root.call("list", {}, (err, res) => {
                const all = {}
                for (const d of res ?? [])
                    all[d.device] = Object.assign({ values: {}, battery: {}, devices: [], info: {} }, d)
                root.devices = all
            })
        }
        // Не только exited: если budsd нет в PATH, процесс не стартует вовсе
        onRunningChanged: {
            if (running)
                return
            root.devices = {}
            for (const id in root.pending)
                root.pending[id]({ code: 2, message: "budsd завершился" }, null)
            root.pending = {}
            root.crashes = !started || alive.running ? root.crashes + 1 : 0
            started = false
            alive.stop()
            // Нет budsd в PATH или он падает — не долбим
            if (root.crashes < 5)
                restart.restart()
            else
                console.warn("buds: budsd падает раз за разом, больше не запускаю")
        }
    }

    // Прожил 10 с — значит, не «упал на старте»
    Timer {
        id: alive
        interval: 10000
    }

    Timer {
        id: restart
        interval: 3000
        onTriggered: proc.running = true
    }
}
