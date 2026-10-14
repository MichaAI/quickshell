#!/usr/bin/env bash
# Тест скоупов: приложения из лончера переживают остановку шелла.
#
#   tests/scopes.sh [ревизия]   — по умолчанию рабочее дерево
#
# Шелл крутится сервисом systemd --user, как в nix/home.nix. Из него
# запускаем «многопроцессное» приложение (sh с фоновым ребёнком) и wl-copy,
# останавливаем сервис — systemd убивает его cgroup — и смотрим, кто выжил
# и в какой cgroup жил.
#
# В облачном контейнере PID 1 — не systemd, и systemd --user без
# /run/systemd/system не стартует: создаём этот маркер сами
. "$(dirname "$0")/lib.sh"

REV=${1:-}
SD=$RUN/sd                                   # XDG_RUNTIME_DIR менеджера
UNIT=qs-test
fails=0

sd() { XDG_RUNTIME_DIR=$SD "$@"; }

if ! sd systemctl --user show-environment >/dev/null 2>&1; then
    mkdir -p /run/systemd/system "$SD" && chmod 700 "$SD"
    XDG_RUNTIME_DIR=$SD setsid -f /usr/lib/systemd/systemd --user > "$RUN/systemd.log" 2>&1 < /dev/null
    for _ in $(seq 50); do sd systemctl --user show-environment >/dev/null 2>&1 && break; sleep 0.1; done
fi
sd systemctl --user show-environment >/dev/null || { log "systemd --user не поднялся, см. $RUN/systemd.log"; exit 1; }

# Приложение: родитель и фоновый ребёнок, как у браузера
mkdir -p "$TEST_HOME/.local/share/applications"
cat > "$TEST_HOME/.local/share/applications/qs-sleeper.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Sleeper
Exec=sh -c "sleep 7701 & exec sleep 7702"
EOF

cleanup() {
    pkill -f "sleep 770[12]" 2>/dev/null || true
    pkill -f "wl-copy -- qs-scope-test" 2>/dev/null || true
}
cleanup
sd systemctl --user stop $UNIT 2>/dev/null || true
sd systemctl --user reset-failed $UNIT 2>/dev/null || true

make_config "$REV"
add_test_ipc
start_sway
start_niri

sd systemd-run --user --unit=$UNIT --quiet \
    --setenv=PATH="$PATH" --setenv=LANG=$LANG --setenv=HOME="$TEST_HOME" \
    --setenv=XDG_RUNTIME_DIR="$SD" --setenv=WAYLAND_DISPLAY="$NIRI" --setenv=NIRI_SOCKET="$NIRI_SOCKET" \
    --setenv=FONTCONFIG_FILE="$FONTCONFIG_FILE" --setenv=__EGL_VENDOR_LIBRARY_FILENAMES="$__EGL_VENDOR_LIBRARY_FILENAMES" \
    --setenv=LIBGL_ALWAYS_SOFTWARE=1 \
    quickshell -p "$RUN/cfg"

ipc() { XDG_RUNTIME_DIR=$SD WAYLAND_DISPLAY=$NIRI quickshell -p "$RUN/cfg" ipc call "$@" 2>/dev/null; }
for _ in $(seq 100); do [ "$(ipc test launch qs-sleeper)" = ok ] && break; sleep 0.2; done
ipc test copy qs-scope-test
sleep 2

cg() { grep name=systemd "/proc/$1/cgroup" 2>/dev/null | cut -d: -f3 || grep '^0::' "/proc/$1/cgroup" | cut -d: -f3; }
for p in $(pgrep -f "sleep 770[12]") $(pgrep -f "wl-copy -- qs-scope-test"); do
    printf '  %-22s %s\n' "$(tr '\0' ' ' < /proc/$p/cmdline | cut -c1-22)" "$(cg $p)"
    case "$(cg $p)" in */app-quickshell-*.scope) ;; *) fails=$((fails + 1)) ;; esac
done

sd systemctl --user stop $UNIT
sleep 1

alive=$( (pgrep -f "sleep 770[12]" || true) | wc -l)
clip=$(WAYLAND_DISPLAY=$NIRI timeout 2 wl-paste 2>/dev/null || true)
echo "после остановки шелла: живых процессов приложения $alive из 2, буфер обмена: «$clip»"
[ "$alive" -eq 2 ] || fails=$((fails + 1))
[ "$clip" = qs-scope-test ] || fails=$((fails + 1))

cleanup
stop_all
[ $fails -eq 0 ] && log "скоупы: всё хорошо" || { log "скоупы: провалов — $fails"; exit 1; }
