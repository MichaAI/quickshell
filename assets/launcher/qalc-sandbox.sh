#!/usr/bin/env bash
# qalc в песочнице bubblewrap для калькулятора лончера.
#
#   qalc-sandbox.sh ARGS…               демон: без сети, домашняя папка — пустой
#                                       tmpfs, конфиг и данные qalc только на чтение
#   qalc-sandbox.sh --rates MIN ARGS…   обновить курсы валют, если им больше MIN
#                                       минут: сеть есть, писать можно только в
#                                       каталог данных qalc. Код 3 — курсы свежие
#
# Внутри видно только замыкание qalc из /nix/store (на других системах —
# /usr и библиотеки), PATH пустой, окружение очищено, все namespaces свои.
# Нет bwrap — запускаем qalc как есть и предупреждаем в stderr.

set -euo pipefail

mode=daemon
maxage=0
if [[ ${1:-} == --rates ]]; then
    mode=rates
    maxage=$2
    shift 2
fi

conf=${XDG_CONFIG_HOME:-$HOME/.config}/qalculate
data=${XDG_DATA_HOME:-$HOME/.local/share}/qalculate
mkdir -p "$conf" "$data"

if [[ $mode == rates && -n $(find "$data" -maxdepth 1 -name rates.json -mmin -"$maxage" 2>/dev/null) ]]; then
    exit 3
fi

qalc=$(command -v qalc) || { echo "qalc-sandbox: qalc не найден" >&2; exit 127; }

if ! command -v bwrap >/dev/null; then
    echo "qalc-sandbox: bwrap не найден — qalc работает БЕЗ песочницы" >&2
    exec "$qalc" "$@"
fi

real=$(readlink -f "$qalc")
args=(
    --unshare-all --die-with-parent --new-session --cap-drop ALL
    --clearenv
    --setenv HOME "$HOME"
    --setenv PATH /var/empty
    --setenv LANG "${LANG:-C.UTF-8}"
    --proc /proc --dev /dev --tmpfs /tmp
    --tmpfs "$HOME"
)
[[ -n ${LC_ALL:-} ]] && args+=(--setenv LC_ALL "$LC_ALL")
[[ -n ${TZ:-} ]] && args+=(--setenv TZ "$TZ")
[[ -n ${XDG_CONFIG_HOME:-} ]] && args+=(--setenv XDG_CONFIG_HOME "$XDG_CONFIG_HOME")
[[ -n ${XDG_DATA_HOME:-} ]] && args+=(--setenv XDG_DATA_HOME "$XDG_DATA_HOME")

# Файл → по его настоящему пути (симлинки NixOS ведут в /nix/store), виден как $1
bind_file() {
    [[ -e $1 ]] || return 0
    args+=(--ro-bind "$(readlink -f "$1")" "$1")
}

# Сам qalc и его библиотеки
if [[ $real == /nix/store/* ]]; then
    # Только замыкание qalc; не смогли спросить nix — весь store, но на чтение
    if closure=$(nix-store -qR "$real" 2>/dev/null) && [[ -n $closure ]]; then
        while IFS= read -r p; do
            args+=(--ro-bind "$p" "$p")
        done <<< "$closure"
    else
        args+=(--ro-bind /nix/store /nix/store)
    fi
else
    for d in /usr /lib /lib64 /lib32 /bin /sbin /etc/ld.so.cache /etc/alternatives; do
        [[ -e $d ]] && args+=(--ro-bind "$d" "$d")
    done
fi

# Локаль и часовой пояс — для дат и десятичного разделителя
if [[ -n ${LOCALE_ARCHIVE:-} && -e $LOCALE_ARCHIVE ]]; then
    la=$(readlink -f "$LOCALE_ARCHIVE")
    args+=(--ro-bind "$la" "$la" --setenv LOCALE_ARCHIVE "$la")
fi
bind_file /etc/localtime

if [[ $mode == rates ]]; then
    # Сеть и всё, что нужно для HTTPS: DNS и сертификаты
    args+=(--share-net)
    for f in /etc/resolv.conf /etc/hosts /etc/nsswitch.conf /etc/ssl/certs/ca-certificates.crt; do
        bind_file "$f"
    done
    if [[ -e /etc/ssl/certs/ca-certificates.crt ]]; then
        args+=(--setenv SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
               --setenv NIX_SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt)
    fi
    args+=(--ro-bind "$conf" "$conf" --bind "$data" "$data")
else
    args+=(--ro-bind "$conf" "$conf" --ro-bind "$data" "$data")
fi

exec bwrap "${args[@]}" -- "$real" "$@"
