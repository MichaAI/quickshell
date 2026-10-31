pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick
import QtQml

// Память лончера между открытиями: попаут пересоздаётся при каждом показе,
// а это живёт вместе с шеллом.
//  • cache — последние данные асинхронных режимов (гифки, перевод, docker…):
//    при возврате список виден сразу, а свежий подтянется следом;
//  • recent — недавнее по режимам (гифки, переводы, QR, nix), лежит на диске.
Singleton {
    id: root

    readonly property int recentMax: 30

    property var cache: ({})
    property var recent: ({})
    // Постоянный анонимный id — Klipy просит customer_id
    property string clientId: ""

    // ===== Кэш (в памяти) =====

    function put(key, value) {
        const c = Object.assign({}, cache)
        c[key] = value
        cache = c
    }

    // ===== Недавнее (на диске) =====

    function recentOf(kind) {
        return recent[kind] ?? []
    }

    // key(x) — по нему повтор вытесняет старую запись
    function remember(kind, entry, key) {
        const k = key(entry)
        const r = Object.assign({}, recent)
        r[kind] = [entry, ...recentOf(kind).filter(x => key(x) !== k)].slice(0, recentMax)
        recent = r
        _save()
    }

    function forget(kind, pred) {
        const r = Object.assign({}, recent)
        r[kind] = recentOf(kind).filter(x => !pred(x))
        recent = r
        _save()
    }

    // ===== Куда передать наработку (Ctrl+⏎) =====
    // Что из этого есть в PATH — проверяем один раз при старте
    readonly property var handoffApps: ["qalculate-gtk", "qalculate-qt", "lazydocker", "k9s", "htop", "btop", "busctl"]
    property var installed: ({})

    function has(c) {
        return installed[c] === true
    }

    // Терминальная программа: своя, а нет — через nix run, без установки.
    // {app, cmd} — подпись для подвала и строка для терминала
    function tui(name, args) {
        const tail = args && args.length ? " " + args.join(" ") : ""
        return has(name)
            ? { app: name, cmd: name + tail }
            : { app: name + " через nix", cmd: "nix run nixpkgs#" + name + (tail ? " --" + tail : "") }
    }

    Process {
        running: true
        command: ["sh", "-c", 'for c; do command -v "$c" >/dev/null && echo "$c"; done', "sh", ...root.handoffApps]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {}
                for (const c of this.text.split("\n")) if (c !== "") m[c] = true
                root.installed = m
            }
        }
    }

    // ===== Ключи API (гифки) =====
    // Не в настройках (они уходят в стор): файл на ключ в keysDir, права 600.
    // Пишутся из лончера (gif key …); QS_GIF_KEY_FILE — путь к готовому
    // секрету (sops-nix, agenix), его ставит модуль home-manager
    readonly property string keysDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share")
        + "/quickshell/keys"
    readonly property var keyFiles: ({
        klipy: keysDir + "/klipy",
        giphy: keysDir + "/giphy",
        gif: Quickshell.env("QS_GIF_KEY_FILE") ?? ""
    })
    property var keys: ({})

    function setKey(name, value) {
        const k = Object.assign({}, keys)
        k[name] = value
        keys = k
    }

    function saveKey(name, value) {
        setKey(name, value)
        Tools.run(["sh", "-c", 'umask 077 && mkdir -p "${2%/*}" && printf "%s\n" "$1" > "$2"', "sh", value, keyFiles[name]])
    }

    function deleteKey(name) {
        setKey(name, "")
        Tools.run(["rm", "-f", keyFiles[name]])
    }

    Instantiator {
        model: Object.keys(root.keyFiles)
        delegate: FileView {
            required property string modelData
            path: root.keyFiles[modelData]
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: root.setKey(modelData, text().trim())
            onLoadFailed: root.setKey(modelData, "")
        }
    }

    readonly property string file: Quickshell.env("HOME") + "/.cache/quickshell-launcher-recent.json"

    function _save() {
        view.setText(JSON.stringify({ id: clientId, recent }) + "\n")
    }

    FileView {
        id: view
        path: root.file
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const v = JSON.parse(text())
                if (v && typeof v.recent === "object") root.recent = v.recent
                if (typeof v?.id === "string") root.clientId = v.id
            } catch (e) {}
        }
    }

    Component.onCompleted: {
        if (clientId === "")
            clientId = Qt.md5(Math.random() + ":" + Date.now()).slice(0, 16)
    }
}
