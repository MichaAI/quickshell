#!/usr/bin/env bash
# Тест лока: за сколько niri закрывает экран и играет ли анимация 3D-авы.
#
#   tests/lock.sh [ревизия]     — по умолчанию рабочее дерево
#
# Сценарии: холодный кеш (QML, шейдеры Quick3D и mesa и снимок авы стёрты —
# как первый лок после обновления), тёплый, и повторные локи после
# разблокировки. Перед первым локом шелл должен снять кадр авы в фоне:
# с него лок и начинается, пока живая ава грузится.
# Ава — лиса из tests/setup.sh с анимацией Survey; вращение выключено,
# так что всё движение авы — от анимации. Лиса порой стоит неподвижно,
# поэтому кадров четыре за ~1.5 с, и считается максимум разницы.
#
# Провал: лок дольше LIMIT_MS (500), ава не шевелится или кадр авы не снялся.
. "$(dirname "$0")/lib.sh"

REV=${1:-}
LIMIT_MS=${LIMIT_MS:-500}
RELOCKS=${RELOCKS:-3}
fails=0

have_fox=false
[ -s "$QST/Fox.glb" ] && have_fox=true && cp "$QST/Fox.glb" "$TEST_HOME/avatar.glb"
$have_fox || log "нет Fox.glb — анимацию не проверяем"

make_config "$REV"
set_setting lockAnimation '"Survey"'
set_setting lockSpinMs 0
add_test_ipc
start_sway

# Сколько пикселей авы изменилось между соседними из 4 кадров (максимум)
avatar_motion() {
    local tag=$1 max=0 v i
    for i in 1 2 3 4; do shot "$RUN/$tag-$i.png"; sleep 0.5; done
    for i in 1 2 3; do
        # Плитка авы: левая верхняя в бенто, 330×330 внутри окна niri
        v=$(magick compare -metric AE -fuzz 5% \
            \( "$RUN/$tag-$i.png" -crop 330x330+620+332 \) \
            \( "$RUN/$tag-$((i + 1)).png" -crop 330x330+620+332 \) null: 2>&1 | cut -d' ' -f1 | cut -d. -f1)
        [ "$v" -gt "$max" ] && max=$v
    done
    echo "$max"
}

locks() { qs_log | grep -c "экран закрыт за" || true; }

# Лок и ожидание новой строки «экран закрыт за N мс»; печатает N
lock_now() {
    local before
    before=$(locks)
    qs_ipc lock lock >/dev/null
    for _ in $(seq 100); do [ "$(locks)" -gt "$before" ] && break; sleep 0.1; done
    [ "$(locks)" -gt "$before" ] && qs_log | sed -n 's/.*lock: экран закрыт за \([0-9]*\) мс.*/\1/p' | tail -1
}

check() {
    local name=$1 ms=$2 motion
    sleep 3                           # аве — догрузиться
    motion=$($have_fox && avatar_motion "$name" || echo "-")
    local verdict=ok
    if [ -z "$ms" ] || [ "$ms" -gt "$LIMIT_MS" ]; then verdict=FAIL; fi
    if $have_fox && [ "$motion" -eq 0 ]; then verdict=FAIL; fi
    [ $verdict = FAIL ] && fails=$((fails + 1))
    local live
    live=$(qs_log | sed -n 's/.*lock: живая ава через \([0-9]*\) мс.*/\1/p' | tail -1)
    printf '%-10s лок %5s мс   живая ава %5s мс   движение авы %5s px   %s\n' \
        "$name" "${ms:-нет}" "${live:--}" "$motion" "$verdict"
}

for mode in cold warm; do
    [ $mode = cold ] && rm -rf "$TEST_HOME/.cache/quickshell/qmlcache" "$TEST_HOME"/.cache/quickshell/q3d* \
        "$TEST_HOME"/.cache/quickshell/qtpipe* "$TEST_HOME"/.cache/qtshader* "$TEST_HOME/.cache/mesa_shader_cache" \
        "$TEST_HOME/.cache/quickshell/lock-avatar-frame"
    start_niri
    start_shell
    # Ждём, пока шелл найдёт аву: на холодном кеше balsam ещё собирает сцену
    wait_log "lock: 3D-ава" 60 || { log "шелл не поднялся:"; qs_log | tail -20; exit 1; }
    if $have_fox && [ $mode = cold ]; then
        wait_log "lock: кадр авы снят" 30 || { log "кадр авы не снялся"; fails=$((fails + 1)); }
    fi
    sleep 2
    check "$mode" "$(lock_now)"
done

# Повторные локи в том же шелле
for i in $(seq 2 $((RELOCKS + 1))); do
    qs_ipc testlock unlock >/dev/null
    sleep 2
    check "relock$i" "$(lock_now)"
done

stop_all
[ $fails -eq 0 ] && log "лок: всё хорошо" || { log "лок: провалов — $fails"; exit 1; }
