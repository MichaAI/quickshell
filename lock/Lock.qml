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
    // Сколько точек рисовать. Не text.length: пароль стираем сразу после
    // отправки в PAM, а точки должны пульсировать, пока он думает
    property int length: 0
    onTextChanged: if (!busy) length = text.length
    property bool busy: false
    property string error: ""
    property int fails: 0               // растёт на каждую ошибку — для тряски поля
    // Caps Lock: по набранным буквам (надёжно при любой раскладке), а пока
    // ничего не набрано — по светодиоду. Светодиод бывает мёртвым: его может
    // не обновлять композитор или его нет на клавиатуре
    property bool capsLed: false
    property var capsTyped: null        // null — ещё не понятно по вводу
    readonly property bool caps: capsTyped !== null ? capsTyped : capsLed
    // Светодиод ожил и переключился — значит, ему можно верить
    onCapsLedChanged: capsTyped = null

    // Вызывается на каждое нажатие в поле пароля
    function noteKey(event) {
        if (event.key === Qt.Key_CapsLock) {
            if (capsTyped !== null)
                capsTyped = !capsTyped
            return
        }
        const t = event.text
        if (t.length !== 1 || t.toLowerCase() === t.toUpperCase())
            return      // не буква
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0
        capsTyped = (t === t.toUpperCase()) !== shift
    }
    property string avatarModel: ""     // ~/avatar.(glb|gltf|fbx|obj), если есть
    property string avatarScene: ""     // она же после balsam — с анимациями

    readonly property string home: Quickshell.env("HOME")
    readonly property string user: Quickshell.env("USER") ?? ""

    readonly property string wallPath: Settings.lockWallpaper.replace(/^~/, home)
    readonly property string wallUrl: wallPath !== "" ? "file://" + wallPath : ""
    // Обои декодируются заранее, в фоне при старте шелла, а не в момент
    // блокировки: эта картинка держит декодированное изображение в кеше
    // Qt, и обои на экране блокировки берут его оттуда сразу. Ключ кеша —
    // путь и sourceSize, умноженный на масштаб окна. У невидимой картинки
    // окна нет, а у поверхности блокировки масштаб дробный и становится
    // известен не сразу — с sourceSize ключи не совпадают, поэтому обе
    // картинки грузят обои в исходном размере. fillMode тоже входит в
    // ключ (PreserveAspectCrop/Fit), так что он тот же, что в LockSurface
    Image {
        visible: false
        source: root.wallUrl
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
    }

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

    // Все пути к блокировке идут сюда. Не полагаемся на сигнал смены
    // состояния WlSessionLock: на настоящем niri он приходил не всегда
    function lock() {
        if (persist.locked)
            return
        text = ""
        error = ""
        modelProbe.running = true
        lockStarted = Date.now()
        persist.locked = true
    }

    // Композитор подтвердил блокировку: экран уже закрыт. Тяжёлое (3D-аву)
    // грузим только после этого, чтобы оно не задерживало первый кадр лока
    readonly property bool secure: sessionLock.secure

    // Сколько экран закрывался: от вызова до подтверждения композитором.
    // niri подтверждает, когда каждый монитор нарисовал первый кадр лока
    property real lockStarted: 0
    Connections {
        target: sessionLock
        function onSecureChanged() {
            if (root.secure && root.lockStarted > 0)
                console.warn("lock: экран закрыт за", Date.now() - root.lockStarted, "мс")
        }
    }

    // Модель ищем и при старте — в логе сразу видно, нашлась ли она
    Component.onCompleted: modelProbe.running = true

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

        // Пароль живёт в памяти шелла как можно меньше: стираем его сразу
        // после отправки, а потом просим сборщик мусора убрать старые
        // строки. Затереть память нулями из QML нельзя — строки в JS
        // неизменяемые, так что это гигиена, а не шред
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.text)
                root.text = ""
            }
        }

        function finish() {
            root.busy = false
            root.text = ""
            root.length = 0
            Qt.callLater(gc)
        }

        onCompleted: result => {
            pam.finish()
            if (result === PamResult.Success) {
                root.error = ""
                persist.locked = false
            } else {
                root.error = result === PamResult.MaxTries ? "Слишком много попыток" : "Неверный пароль"
                root.fails++
            }
        }

        onError: {
            pam.finish()
            root.error = "PAM не отвечает"
            root.fails++
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: persist.locked

        WlSessionLockSurface {
            color: Theme.crust

            LockSurface {
                anchors.fill: parent
                ctx: root
            }
        }
    }

    // Ищем ~/avatar.* и, если есть balsam, один раз переводим модель в
    // QML-сцену в кеше: RuntimeLoader анимации не проигрывает, а сцена —
    // да. Кеш пересобирается, когда модель меняется. Вывод — две строки:
    // модель и сцена (пустая, если balsam'а нет или он не справился)
    Process {
        id: modelProbe
        command: ["sh", "-c", `
            for e in glb gltf fbx obj; do
                [ -f "$1/avatar.$e" ] && { src="$1/avatar.$e"; break; }
            done
            [ -n "\${src:-}" ] || exit 0
            echo "$src"
            command -v balsam >/dev/null || { echo; exit 0; }
            cache="\${XDG_CACHE_HOME:-$1/.cache}/quickshell/lock-avatar"
            # Ключ кеша — настоящие пути модели и balsam'а: ~/avatar.glb
            # бывает ссылкой в /nix/store, и новая модель — это новая цель
            # ссылки, а не новое время файла. А после обновления Qt старая
            # сцена может не прочитаться — пересобираем. Ключевые кадры
            # пишем прямо в QML: двоичные .qad читает не всякий Timeline
            key="v2 $(readlink -f "$src") $(readlink -f "$(command -v balsam)")"
            if [ "$(cat "$cache/source" 2>/dev/null)" != "$key" ] || [ "$src" -nt "$cache/source" ]; then
                rm -rf "$cache" && mkdir -p "$cache"
                QT_QPA_PLATFORM=offscreen balsam --manualAnimations --disable-useBinaryKeyframes \
                    -o "$cache" "$src" >&2 \
                    && echo "$key" > "$cache/source"
            fi
            [ -f "$cache/source" ] && ls "$cache"/*.qml 2>/dev/null | head -n 1
            echo`,
            "qs", root.home]
        stdout: StdioCollector {
            onStreamFinished: {
                const [model, scene] = this.text.split("\n")
                root.avatarModel = model ?? ""
                root.avatarScene = scene ?? ""
                console.warn("lock: 3D-ава:", root.avatarModel || "нет ~/avatar.(glb|gltf|fbx|obj)",
                             root.avatarModel === "" ? ""
                             : root.avatarScene !== "" ? "→ сцена " + root.avatarScene
                             : "без анимаций (balsam нет или он не справился)")
            }
        }
    }

    // Caps Lock видно только по светодиоду в sysfs: Wayland его не сообщает
    Process {
        id: capsProbe
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.capsLed = this.text.split("\n").some(s => parseInt(s) > 0)
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
            root.lock()
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock()
        }
    }
}
