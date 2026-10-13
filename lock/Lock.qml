import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../config"
import "../services"

// Экран блокировки: `qs ipc call lock lock`.
// Экран держит закрытым протокол ext-session-lock: если шелл упадёт,
// композитор не разблокирует, а оставит экран закрытым. Пароль проверяет
// PAM (lock/pam/password.conf — только pam_unix, без отпечатков и прочего).
Scope {
    id: root

    // Общее состояние для всех мониторов: печатать можно на любом
    property string text: ""
    property bool busy: false
    property string error: ""
    property int fails: 0               // растёт на каждую ошибку — для тряски поля
    property bool caps: false
    property string avatarModel: ""     // ~/avatar.(glb|gltf|fbx|obj), если есть

    readonly property string home: Quickshell.env("HOME")
    readonly property string user: Quickshell.env("USER") ?? ""

    // Перезагрузка конфига при активном локе в quickshell 0.3.2 роняет
    // весь шелл (новый лок пытается занять уже занятые мониторы), поэтому
    // пока экран закрыт, правки файлов не подхватываем.
    Binding {
        target: Quickshell
        property: "watchFiles"
        value: false
        when: persist.locked
    }

    // А если перезагрузка всё же случится — лок не должен открыться:
    // состояние переживает её, и в худшем случае шелл падает, а экран
    // остаётся закрытым (niri показывает красный фон)
    PersistentProperties {
        id: persist
        reloadableId: "lockState"
        property bool locked: false
    }

    function submit() {
        if (busy || text === "")
            return
        busy = true
        error = ""
        pam.start()
    }

    PamContext {
        id: pam
        configDirectory: Quickshell.shellPath("lock/pam")
        config: "password.conf"

        onPamMessage: {
            if (this.responseRequired)
                this.respond(root.text)
        }

        onCompleted: result => {
            root.busy = false
            root.text = ""
            if (result === PamResult.Success) {
                root.error = ""
                persist.locked = false
            } else {
                root.error = result === PamResult.MaxTries ? "Слишком много попыток" : "Неверный пароль"
                root.fails++
            }
        }

        onError: {
            root.busy = false
            root.text = ""
            root.error = "PAM не отвечает"
            root.fails++
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: persist.locked

        onLockedChanged: {
            if (!locked)
                return
            root.text = ""
            root.error = ""
            modelProbe.running = true
        }

        WlSessionLockSurface {
            color: Theme.crust

            LockSurface {
                anchors.fill: parent
                ctx: root
            }
        }
    }

    Process {
        id: modelProbe
        command: ["sh", "-c",
            'for e in glb gltf fbx obj; do [ -f "$1/avatar.$e" ] && { echo "$1/avatar.$e"; break; }; done',
            "qs", root.home]
        stdout: StdioCollector {
            onStreamFinished: {
                root.avatarModel = this.text.trim()
                console.info("lock: 3D-ава:", root.avatarModel || "нет ~/avatar.(glb|gltf|fbx|obj)")
            }
        }
    }

    // Caps Lock видно только по светодиоду в sysfs: Wayland его не сообщает
    Process {
        id: capsProbe
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.caps = this.text.split("\n").some(s => parseInt(s) > 0)
        }
    }

    Timer {
        running: sessionLock.locked
        interval: 250
        repeat: true
        triggeredOnStart: true
        onTriggered: capsProbe.running = true
    }

    Connections {
        target: Ui
        function onLockRequested() {
            persist.locked = true
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            persist.locked = true
        }
    }
}
