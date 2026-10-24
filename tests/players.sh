#!/usr/bin/env bash
# Тест выбора плеера (services/Players.qml): кого показывает шелл, когда
# плееры играют, встают на паузу, выбираются руками и закрываются.
#
#   tests/players.sh [ревизия]  — по умолчанию рабочее дерево
#
# Плееры — mpv с mpris, тишина из lavfi в никуда (--ao=null), на своей
# шине: настоящие плееры сессии в тест не попадают. Переключение на
# другой играющий — через switchDelay (3 с), остальное — сразу
. "$(dirname "$0")/lib.sh"

REV=${1:-}
fails=0

start_bus
make_config "$REV"
add_test_ipc
start_sway
start_niri
start_shell

playerctl() { "$QST/playerctl/bin/playerctl" "$@" 2>/dev/null || true; }
# Имя на шине — mpv.instance-<случайное>, запоминаем при запуске
pctl() { playerctl -p "$(cat "$RUN/$1.name")" "${@:2}"; }

# Плеер: a или b. --log-file — чтобы $RUN был в строке запуска (см. alive)
start_player() {
    local before name
    before=$(playerctl -l)
    setsid "$QST/mpv/bin/mpv" --no-config --no-video --ao=null --loop=inf \
        --script="$QST/mpvScripts.mpris/share/mpv/scripts/mpris.so" \
        --log-file="$RUN/$1.mpv.log" "av://lavfi:sine" > /dev/null 2>&1 < /dev/null &
    echo $! > "$RUN/$1.pid"
    for _ in $(seq 50); do
        name=$(playerctl -l | grep -vxF -- "$before" | head -1 || true)
        [ -n "$name" ] && echo "$name" > "$RUN/$1.name" && [ "$(pctl "$1" status)" = Playing ] && return
        sleep 0.1
    done
    log "плеер $1 не заиграл, см. $RUN/$1.mpv.log"; exit 1
}

# Кого показывает шелл: a, b или что вернул IPC
shown() {
    local name p
    name=$(qs_ipc test player)
    for p in a b; do
        [ -f "$RUN/$p.pid" ] && [ "$name" = "org.mpris.MediaPlayer2.$(cat "$RUN/$p.name")" ] \
            && { echo $p; return; }
    done
    echo "${name:-нет ответа}"
}

expect() {
    local what=$1 want=$2 got
    got=$(shown)
    if [ "$got" = "$want" ]; then
        printf '  ok    %s\n' "$what"
    else
        printf '  FAIL  %s: показан %s, ждали %s\n' "$what" "$got" "$want"
        fails=$((fails + 1))
    fi
}

for _ in $(seq 100); do [ -n "$(qs_ipc test player)" ] && break; sleep 0.2; done

start_player a
sleep 1
expect "играет один — он" a

start_player b
sleep 1
expect "заиграл второй — остаёмся на первом" a

pctl a pause
sleep 1
expect "первый на паузе 1 с — ещё он" a
sleep 3
expect "первый на паузе 4 с — второй" b

pctl b pause
sleep 4
expect "не играет никто — остаёмся на последнем" b

pctl a play
sleep 1
expect "первый заиграл 1 с назад — ещё второй" b
sleep 3
expect "первый играет 4 с — он" a

qs_ipc test selectPlayer "org.mpris.MediaPlayer2.$(cat "$RUN/b.name")" >/dev/null
sleep 0.5
expect "выбрали второй руками — сразу он" b

qs_ipc test selectPlayer "org.mpris.MediaPlayer2.$(cat "$RUN/a.name")" >/dev/null
sleep 0.5
expect "выбрали обратно первый — сразу он" a

pctl a pause
for p in b a b; do
    qs_ipc test selectPlayer "org.mpris.MediaPlayer2.$(cat "$RUN/$p.name")" >/dev/null
    sleep 0.5
    expect "оба на паузе, выбрали $p — сразу он" $p
done

stop b
sleep 1
expect "выбранный закрыли — сразу первый" a

[ $fails -eq 0 ] && log "плееры: всё хорошо" || { log "плееры: провалов — $fails"; exit 1; }
