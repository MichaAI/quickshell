pragma ComponentBehavior: Bound
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
    property string avatarKey: ""       // меняется вместе с моделью и Qt
    property string frameDir: ""        // кеш готового кадра авы

    // Готовый кадр 3D-авы. Живую аву на лок не пускаем до подтверждения
    // блокировки: её разбор и шейдеры Quick3D держали первый кадр лока.
    // Но и ~/.face на её месте — это мигание чужим лицом. Поэтому при
    // старте шелла ава один раз рендерится в фоне и снимается в той позе,
    // с которой живая ава начинает. Заодно прогреваются дисковые кеши
    // шейдеров Quick3D и QML. На локе сначала снимок, и живая ава
    // подменяет его незаметно. Снимок и габариты модели лежат в кеше и
    // переживают перезапуск; переснимаем, когда меняется модель, Qt или
    // то, как ава выглядит
    readonly property string frameKey: avatarKey === "" ? "" : [
        "v1", avatarKey, avatarScene, Settings.lockColumn, Settings.lockModelSize, Settings.lockAnimation,
        Dither.avatarPixel, Dither.avatarDark, Dither.avatarMid, Dither.avatarLight, Dither.avatarBright
    ].join(" ")
    property var frame: null            // frame.json: {key, file, lo, hi}
    property string frameReadPath: ""   // для какого пути frame.json уже прочитан
    readonly property bool frameFresh: frameKey !== "" && frame?.key === frameKey
    readonly property string avatarFrame: frameFresh ? "file://" + frameDir + "/" + frame.file : ""
    readonly property var avatarBounds: frameFresh && frame.lo ? {
        lo: Qt.vector3d(frame.lo[0], frame.lo[1], frame.lo[2]),
        hi: Qt.vector3d(frame.hi[0], frame.hi[1], frame.hi[2])
    } : null
    property bool shotFailed: false     // без QtQuick3D или модель не открылась
    readonly property bool needShot: frameKey !== "" && frameReadPath === frameFile.path
                                     && !frameFresh && !shotFailed && !persist.locked

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
        capsTyped = null    // с прошлого лока Caps могли переключить
        capsFind.running = true
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

    FileView {
        id: frameFile
        path: root.frameDir !== "" ? root.frameDir + "/frame.json" : ""
        printErrors: false
        onLoaded: {
            try {
                root.frame = JSON.parse(text())
            } catch (e) {
                root.frame = null
            }
            root.frameReadPath = path
        }
        onLoadFailed: {
            root.frame = null
            root.frameReadPath = path
        }
    }

    // Снимок декодируем заранее, как обои: лок берёт его из кеша Qt.
    // Свойства — те же, что у картинки в LockSurface, иначе ключ кеша другой
    Image {
        visible: false
        source: root.avatarFrame
        asynchronous: true
    }

    // Фоновый рендер авы для снимка: окно в пиксель, прозрачное и
    // сквозное для мыши, а сама ава — за его краем. Qt Quick 3D рисует
    // её в свою текстуру и за краем, так что снимается она целиком, а
    // на экране ничего нет. Окно живёт, пока снимок не готов
    LazyLoader {
        active: root.needShot

        PanelWindow { // qmllint disable uncreatable-type
            id: shotWin
            anchors { top: true; left: true }
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:lock-avatar"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            readonly property real started: Date.now()

            // Через Loader, как и на локе: без QtQuick3D он просто не
            // загрузится, а лок останется
            Loader {
                id: shot
                x: -width - 1
                width: Settings.lockColumn
                height: Settings.lockColumn
                source: "Avatar3D.qml"
                asynchronous: true
                onLoaded: {
                    // Avatar3D — по строке, без типа: иначе лок зависел бы от QtQuick3D
                    // qmllint disable missing-property
                    shot.item.still = true
                    shot.item.scene = Qt.binding(() => root.avatarScene !== "" ? "file://" + root.avatarScene : "")
                    shot.item.model = Qt.binding(() => "file://" + root.avatarModel)
                    // qmllint enable missing-property
                }
                onStatusChanged: if (status === Loader.Error) root.shotFailed = true
            }

            // Готова — значит, меши измерены, то есть уже нарисованы. Ещё
            // чуть ждём, чтобы в кадре наверняка была вся модель
            Timer {
                running: shot.status === Loader.Ready && (shot.item?.ready ?? false)
                interval: 300
                onTriggered: {
                    const key = root.frameKey
                    const a = shot.item
                    a.grabToImage(r => {
                        const file = "frame-" + Qt.md5(key) + ".png"
                        if (!r.saveToFile(root.frameDir + "/" + file)) {
                            console.warn("lock: кадр авы не записался в", root.frameDir)
                            root.shotFailed = true
                            return
                        }
                        const frame = {
                            key, file,
                            lo: [a.lo.x, a.lo.y, a.lo.z],
                            hi: [a.hi.x, a.hi.y, a.hi.z]
                        }
                        frameFile.setText(JSON.stringify(frame))
                        root.frame = frame
                        frameClean.command = ["sh", "-c",
                            'cd "$1" && for f in frame-*.png; do [ "$f" = "$2" ] || rm -f -- "$f"; done',
                            "sh", root.frameDir, file]
                        frameClean.running = true
                        console.warn("lock: кадр авы снят за", Date.now() - shotWin.started, "мс")
                    })
                }
            }

            // Модель так и не открылась — не держим окно вечно
            Timer {
                running: true
                interval: 60000
                onTriggered: {
                    console.warn("lock: кадр авы не снялся за минуту — на локе будет ~/.face")
                    root.shotFailed = true
                }
            }
        }
    }

    // Старые снимки — от прежних моделей и настроек
    Process {
        id: frameClean
    }

    // Модель ищем и при старте — в логе сразу видно, нашлась ли она.
    // Светодиоды Caps — тоже: лок мог пережить перезагрузку шелла
    Component.onCompleted: {
        modelProbe.running = true
        capsFind.running = true
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
    // да. Кеш пересобирается, когда модель меняется. Вывод — четыре строки:
    // модель, сцена (пустая, если balsam'а нет или он не справился), ключ
    // модели и папка для готового кадра авы
    Process {
        id: modelProbe
        command: ["sh", "-c", `
            for e in glb gltf fbx obj; do
                [ -f "$1/avatar.$e" ] && { src="$1/avatar.$e"; break; }
            done
            [ -n "\${src:-}" ] || exit 0
            base="\${XDG_CACHE_HOME:-$1/.cache}/quickshell"
            cache="$base/lock-avatar"
            # Ключ кеша — настоящие пути модели и balsam'а: ~/avatar.glb
            # бывает ссылкой в /nix/store, и новая модель — это новая цель
            # ссылки, а не новое время файла. А после обновления Qt старая
            # сцена может не прочитаться — пересобираем. Время правки — на
            # случай модели, которую перезаписали на месте
            balsam=$(command -v balsam || true)
            key="v2 $(readlink -f "$src") $(stat -Lc %Y "$src") $(readlink -f "$balsam")"
            scene=
            if [ -n "$balsam" ]; then
                # Ключевые кадры пишем прямо в QML: двоичные .qad читает не всякий Timeline
                if [ "$(cat "$cache/source" 2>/dev/null)" != "$key" ]; then
                    rm -rf "$cache" && mkdir -p "$cache"
                    QT_QPA_PLATFORM=offscreen balsam --manualAnimations --disable-useBinaryKeyframes \
                        -o "$cache" "$src" >&2 \
                        && echo "$key" > "$cache/source"
                fi
                [ -f "$cache/source" ] && scene=$(ls "$cache"/*.qml 2>/dev/null | head -n 1)
            fi
            mkdir -p "$base/lock-avatar-frame"
            printf '%s\n' "$src" "$scene" "$key" "$base/lock-avatar-frame"`,
            "qs", root.home]
        stdout: StdioCollector {
            onStreamFinished: {
                const [model, scene, key, frameDir] = this.text.split("\n")
                root.avatarModel = model ?? ""
                root.avatarScene = scene ?? ""
                root.avatarKey = key ?? ""
                root.frameDir = frameDir ?? ""
                console.warn("lock: 3D-ава:", root.avatarModel || "нет ~/avatar.(glb|gltf|fbx|obj)",
                             root.avatarModel === "" ? ""
                             : root.avatarScene !== "" ? "→ сцена " + root.avatarScene
                             : "без анимаций (balsam нет или он не справился)")
            }
        }
    }

    // Caps Lock видно только по светодиоду в sysfs: Wayland его не сообщает.
    // Светодиоды ищем раз за лок (клавиатуру могли подключить), потом
    // только перечитываем файлы — без процесса на каждый опрос
    property var capsLeds: []
    Process {
        id: capsFind
        command: ["sh", "-c", 'for f in /sys/class/leds/*::capslock/brightness; do [ -e "$f" ] && echo "$f"; done']
        stdout: StdioCollector {
            onStreamFinished: root.capsLeds = this.text.split("\n").filter(s => s !== "")
        }
    }

    Instantiator {
        id: capsViews
        model: root.capsLeds
        delegate: FileView {
            required property string modelData
            path: modelData
            printErrors: false
            onLoaded: root.capsLed = [...Array(capsViews.count).keys()]
                .some(i => parseInt(capsViews.objectAt(i)?.text() ?? "") > 0)
        }
    }

    Timer {
        running: sessionLock.locked && capsViews.count > 0
        interval: 250
        repeat: true
        onTriggered: {
            for (let i = 0; i < capsViews.count; i++)
                capsViews.objectAt(i)?.reload()
        }
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
