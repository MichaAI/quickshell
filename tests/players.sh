#!/usr/bin/env bash
# Тест выбора плеера (services/Players.qml): кого показывает шелл, когда
# плееры играют, встают на паузу, выбираются руками и закрываются.
#
#   tests/players.sh [ревизия]  — по умолчанию рабочее дерево
#
# Плееры — mpv с mpris, тишина из lavfi в никуда (--ao=null), на своей
# шине: настоящие плееры сессии в тест не попадают. Заигравший плеер
# показывается сразу (через startDelay), с замолчавшего на другой
# играющий — через stopDelay
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
    setsid "$QST/mpv/bin/mpv" --no-config --no-video --ao=null --loop-playlist=inf \
        --script="$QST/mpvScripts.mpris/share/mpv/scripts/mpris.so" \
        --log-file="$RUN/$1.mpv.log" "av://lavfi:sine=frequency=440" "av://lavfi:sine=frequency=880" \
        > /dev/null 2>&1 < /dev/null &
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

# Смена трека: название ни на миг не «Ничего не играет» и меняется
before=$(qs_ipc test title)
pctl a next
blank=0
for _ in $(seq 20); do
    [ "$(qs_ipc test title)" = "Ничего не играет" ] && blank=$((blank + 1))
    sleep 0.05
done
sleep 0.5
after=$(qs_ipc test title)
if [ $blank -eq 0 ] && [ -n "$after" ] && [ "$after" != "$before" ]; then
    printf '  ok    смена трека — название без провала: %s → %s\n' "$before" "$after"
else
    printf '  FAIL  смена трека: «Ничего не играет» %s раз из 20, %s → %s\n' $blank "$before" "$after"
    fails=$((fails + 1))
fi

start_player b
sleep 1
expect "заиграл второй — сразу он" b

pctl b pause
sleep 0.5
expect "второй на паузе 0.5 с, первый играет — ещё второй" b
sleep 1.5
expect "второй на паузе 2 с — первый" a

pctl a pause
sleep 3
expect "не играет никто — остаёмся на последнем" a

pctl b play
sleep 0.8
expect "второй заиграл — сразу он" b

# Мигнул: заиграл и тут же встал — не переключаемся
pctl a play; sleep 0.1; pctl a pause
sleep 1
expect "первый мигнул — остаёмся на втором" b

# Пауза между треками: показанный на миг замолчал, другой играет
pctl a play
sleep 0.8
expect "первый заиграл — он" a
pctl a pause; sleep 0.4; pctl a play
sleep 2
expect "первый на 0.4 с замолчал, второй играет — остаёмся" a

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
