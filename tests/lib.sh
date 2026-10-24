# Общее для тестов: шелл в настоящем niri без экрана.
#
#   sway (headless) — даёт вывод Wayland
#   └─ niri (вложенным окном) — тот самый композитор
#      └─ quickshell -p <копия конфига>
#
# Инструменты собирает .claude/hooks/session-start.sh (или tests/setup.sh)
# в $QST. Скриншоты — grim со стороны sway: он видит окно niri целиком.
#
# Подключение: . tests/lib.sh

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$REPO/tests/qst.sh"                   # QST — собранные инструменты
RUN=${RUN:-/tmp/qst}                     # сокеты, логи, копия конфига; путь
                                         # короткий: в sun_path влезает 108 байт
export LANG=C.UTF-8

[ -x "$QST/quickshell/bin/quickshell" ] || {
    echo "нет инструментов в $QST — запусти tests/setup.sh" >&2
    exit 1
}

PATH=$QST/quickshell/bin:$PATH
for d in "$QST"/*/bin; do PATH=$PATH:$d; done
export PATH

# GL из mesa в $QST через glvnd — не из системы, так что одинаково везде.
# Рендер на видеокарте, если есть доступный render node, иначе (облако)
# на процессоре, llvmpipe. QST_GPU=1/0 — выбрать руками. Времена лока на
# GPU и llvmpipe не сравнимы: сравнивать ревизии — в одном режиме
printf '{"file_format_version":"1.0.0","ICD":{"library_path":"%s"}}\n' \
    "$QST/mesa/lib/libEGL_mesa.so.0" > "$QST/egl.json" 2>/dev/null || true
export __EGL_VENDOR_LIBRARY_FILENAMES=$QST/egl.json
export GBM_BACKENDS_PATH=$QST/mesa/lib/gbm
RENDER_NODE=${RENDER_NODE:-$(ls /dev/dri/renderD* 2>/dev/null | head -1 || true)}
if [ -z "${QST_GPU:-}" ]; then
    QST_GPU=0
    [ -n "$RENDER_NODE" ] && [ -r "$RENDER_NODE" ] && [ -w "$RENDER_NODE" ] && QST_GPU=1
fi
if [ "$QST_GPU" = 1 ]; then
    unset LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER
else
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
fi

# Шрифт из Theme.font
cat > "$QST/fonts.conf" 2>/dev/null <<EOF || true
<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig><dir>$QST/nerd-fonts.jetbrains-mono/share/fonts</dir><cachedir>$RUN/fc</cachedir></fontconfig>
EOF
export FONTCONFIG_FILE=$QST/fonts.conf

# Тесты могут идти из живой сессии: ничего из её окружения не должно
# дотянуться до настоящего композитора
unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY NIRI_SOCKET SWAYSOCK I3SOCK

mkdir -p "$RUN/rt" "$RUN/home"
chmod 700 "$RUN/rt"
export XDG_RUNTIME_DIR=$RUN/rt
TEST_HOME=$RUN/home
SWAY=wayland-1                      # WAYLAND_DISPLAY со стороны sway
NIRI=$RUN/rt/wayland-niri           # и со стороны niri

log() { printf '\033[1m%s\033[0m\n' "$*" >&2; }

# Процессы тестов — только по pid-файлам в $RUN: по имени (pkill niri)
# или строке запуска (pkill -f) попадает и настоящий niri, и чужие шеллы.
# setsid без -f не форкается, так что $! — pid самого процесса

# Жив ли процесс из $RUN/<имя>.pid и наш ли он ещё (pid мог уйти другому)
alive() {
    local f=$RUN/$1.pid
    [ -f "$f" ] && grep -qF "$RUN" "/proc/$(cat "$f")/cmdline" 2>/dev/null
}

stop() {
    alive "$1" && kill "$(cat "$RUN/$1.pid")" 2>/dev/null || true
    rm -f "$RUN/$1.pid"
}

# Прибить всё, что запускали тесты
stop_all() {
    stop qs
    stop niri
    stop sway
    sleep 0.5
}

start_sway() {
    local renderer=(WLR_RENDERER=pixman)
    [ "$QST_GPU" = 1 ] && renderer=(WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE="$RENDER_NODE")
    [ -S "$XDG_RUNTIME_DIR/$SWAY" ] && alive sway \
        && [ "$(cat "$RUN/sway.gpu" 2>/dev/null)" = "$QST_GPU" ] && return
    stop sway
    rm -f "$XDG_RUNTIME_DIR/$SWAY" "$XDG_RUNTIME_DIR/$SWAY.lock"
    echo 'output HEADLESS-1 resolution 1920x1080' > "$RUN/sway.conf"
    echo "$QST_GPU" > "$RUN/sway.gpu"
    log "рендер: $([ "$QST_GPU" = 1 ] && echo "GPU, $RENDER_NODE" || echo "llvmpipe")"
    env WLR_BACKENDS=headless "${renderer[@]}" WLR_LIBINPUT_NO_DEVICES=1 \
        setsid sway -c "$RUN/sway.conf" > "$RUN/sway.log" 2>&1 < /dev/null &
    echo $! > "$RUN/sway.pid"
    for _ in $(seq 50); do [ -S "$XDG_RUNTIME_DIR/$SWAY" ] && return; sleep 0.1; done
    echo "sway не поднялся, см. $RUN/sway.log" >&2; exit 1
}

# Свежий niri: у лока своё состояние в композиторе, тесты его не делят
start_niri() {
    alive niri && { stop niri; sleep 0.5; }
    printf 'hotkey-overlay {\n    skip-at-startup\n}\ninput {\n    keyboard {\n        xkb {\n            layout "us,ru"\n        }\n    }\n}\n' > "$RUN/niri.kdl"
    rm -f "$NIRI" "$NIRI.lock" "$XDG_RUNTIME_DIR"/niri.*.sock
    (cd "$RUN" && WAYLAND_DISPLAY=$SWAY exec setsid niri -c "$RUN/niri.kdl" > "$RUN/niri.log" 2>&1 < /dev/null) &
    echo $! > "$RUN/niri.pid"
    NIRI_SOCKET=
    for _ in $(seq 50); do
        NIRI_SOCKET=$(ls "$XDG_RUNTIME_DIR"/niri.*.sock 2>/dev/null | tail -1) && [ -n "$NIRI_SOCKET" ] && break
        sleep 0.1
    done
    [ -n "$NIRI_SOCKET" ] || { echo "niri не поднялся, см. $RUN/niri.log" >&2; exit 1; }
    export NIRI_SOCKET
    sleep 1
    NIRI=$XDG_RUNTIME_DIR/$(sed -n 's/.*listening on Wayland socket: \([^ ]*\).*/\1/p' "$RUN/niri.log" | sed 's/\x1b\[[0-9;]*m//g' | tail -1)
}

# Копия конфига: ревизия или рабочее дерево (по умолчанию). OVERLAY —
# файлы рабочего дерева поверх ревизии, например лог времени лока в
# старую версию: OVERLAY=lock/Lock.qml tests/lock.sh <старая ревизия>
make_config() {
    local rev=${1:-}
    rm -rf "$RUN/cfg" && mkdir -p "$RUN/cfg"
    if [ -n "$rev" ]; then
        git -C "$REPO" archive "$rev" | tar -x -C "$RUN/cfg"
    else
        (cd "$REPO" && git ls-files -co --exclude-standard | grep -v '^tests/' \
            | tar -c --ignore-failed-read -T - 2>/dev/null) | tar -x -C "$RUN/cfg"
    fi
    for f in ${OVERLAY:-}; do cp "$REPO/$f" "$RUN/cfg/$f"; done
}

# Подставить значение в config/Settings.qml копии: set_setting lockSpinMs 0
set_setting() {
    sed -i "s|^\( *readonly property [^ ]* $1: \)[^/]*|\1$2 |" "$RUN/cfg/config/Settings.qml"
}

# Тестовые IPC-ручки: только в копии, в репо их нет. Открыть лок снаружи —
# дыра, а PAM в контейнере не работает (nix-овый pam_unix не читает учётки
# Ubuntu), так что разблокировка тут — в обход пароля
add_test_ipc() {
    python3 - "$RUN/cfg" <<'EOF'
import sys
cfg = sys.argv[1]
def append(path, text):
    s = open(path).read()
    i = s.rstrip().rfind('}')
    open(path, 'w').write(s[:i] + text + '}\n')
append(cfg + '/lock/Lock.qml', '''
    IpcHandler {
        target: "testlock"
        function unlock(): void { persist.locked = false }
        function state(): string { return "locked=" + sessionLock.locked + " secure=" + sessionLock.secure }
    }
''')
append(cfg + '/shell.qml', '''
    IpcHandler {
        target: "test"
        function launch(id: string): string {
            const a = DesktopEntries.applications.values.find(e => e.id === id)
            if (!a) return "нет приложения " + id
            Apps.launch(a)
            return "ok"
        }
        function copy(text: string): void { Tools.copy(text) }
    }
''')
EOF
}

# Запустить шелл с копией конфига внутри niri
start_shell() {
    alive qs && { stop qs; sleep 0.5; }
    HOME=$TEST_HOME XDG_CACHE_HOME=$TEST_HOME/.cache WAYLAND_DISPLAY=$NIRI \
        setsid quickshell -p "$RUN/cfg" > "$RUN/qs.log" 2>&1 < /dev/null &
    echo $! > "$RUN/qs.pid"
    sleep 0.3
}

qs_ipc() { WAYLAND_DISPLAY=$NIRI quickshell -p "$RUN/cfg" ipc call "$@" 2>/dev/null; }

# Лог шелла без цветов
qs_log() { sed 's/\x1b\[[0-9;]*m//g' "$RUN/qs.log"; }

# Ждать строку в логе шелла
wait_log() {
    local pattern=$1 timeout=${2:-20}
    for _ in $(seq $((timeout * 10))); do qs_log | grep -q -- "$pattern" && return 0; sleep 0.1; done
    return 1
}

shot() { WAYLAND_DISPLAY=$SWAY grim "$1"; }
