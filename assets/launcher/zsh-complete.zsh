#!/usr/bin/env zsh
# Сервер автодополнения для лончера: держит один интерактивный zsh в zpty
# (с твоим ~/.zshrc, т.е. с настоящим compsys, алиасами и zstyle) и
# отвечает на запросы из stdin.
#
#   stdin:  C<id>\t<буфер>     → <id>\tM\t<вставка>\t<описание> … <id>\tE
#           H                  → H\t<команда> … (свежие первыми) H\tE
#   (в командах из истории переводы строк приходят как \n-литерал)

zmodload zsh/zpty || exit 1
setopt localoptions noshwordsplit

export QS_LAUNCHER_COMPLETE=1   # можно проверять в .zshrc и пропускать тяжёлое

# Свой ZDOTDIR: он подгружает твои .zshenv/.zshrc, а потом нашу настройку.
# Так ничего не набирается в строке и не попадает в историю.
zdot=$(mktemp -d -t qs-zcomp.XXXXXX)
trap 'rm -rf $zdot; zpty -d z 2>/dev/null' EXIT
export QS_ORIG_ZDOTDIR=${ZDOTDIR:-$HOME} QS_ZDOT=$zdot
cat > $zdot/.zshenv <<'ZENV'
ZDOTDIR=$QS_ORIG_ZDOTDIR
[[ -r $ZDOTDIR/.zshenv ]] && source $ZDOTDIR/.zshenv
QS_USER_ZDOTDIR=$ZDOTDIR
ZDOTDIR=$QS_ZDOT
ZENV
cat > $zdot/.zshrc <<'ZRC'
ZDOTDIR=$QS_USER_ZDOTDIR
[[ -r $ZDOTDIR/.zshrc ]] && source $ZDOTDIR/.zshrc
source $QS_ZDOT/setup.zsh
ZRC

# Ждём строку $1 из pty (с таймаутом в секундах $2)
await() {
    local chunk acc= deadline=$(( SECONDS + ${2:-10} ))
    while (( SECONDS < deadline )); do
        if zpty -r -t z chunk; then
            acc+=$chunk
            [[ $acc == *$1* ]] && return 0
        else
            sleep 0.01
        fi
    done
    return 1
}

cat > $zdot/setup.zsh <<'SETUP'
# Историю читаем сами при каждом запросе, а свою никуда не пишем
__qs_histfile=$HISTFILE
unset HISTFILE
unsetopt share_history inc_append_history inc_append_history_time
PROMPT= RPROMPT= PS2= PS3= PS4=
precmd_functions=() preexec_functions=()
unset zle_bracketed_paste
bindkey -e
autoload -Uz compinit
(( $+functions[compdef] )) || compinit -C -d ${XDG_CACHE_HOME:-$HOME/.cache}/qs-zcompdump
# compprefuncs/comppostfuncs сбрасываются после каждого дополнения — ставим заново
__qs_complete() {
    compprefuncs=( __qs_begin )
    comppostfuncs=( __qs_end )
    zle complete-word
}
zle -N __qs_complete
bindkey '^I' __qs_complete
zstyle ':completion:*' list-grouped false
zstyle ':completion:*' insert-tab false
zstyle ':completion:*' list-prompt ''
zstyle ':completion:*' select-prompt ''
zstyle ':completion:*' menu false
__qs_begin() { print -rn -- $'\x1d' }
__qs_end() { print -rn -- $'\x1c' }
compadd() {
    # Служебные вызовы (-O/-A/-D) пропускаем как есть
    if [[ ${@[1,(i)(-|--)]} == *-(O|A|D)\ * ]]; then
        builtin compadd "$@"
        return $?
    fi
    setopt localoptions extendedglob
    typeset -a __hits __dscr __tmp
    # -d бывает склеен с другими флагами: -ld names_d
    integer __di=${@[(I)-[a-zA-Z]#d]}
    if (( __di )); then
        __tmp=${@[__di+1]}
        if [[ $__tmp == \(* ]]; then
            eval "__dscr=$__tmp"
        else
            __dscr=( "${(@P)__tmp}" )
        fi
    fi
    builtin compadd -A __hits -D __dscr "$@"
    setopt localoptions norcexpandparam extendedglob
    typeset -A apre hpre hsuf asuf
    zparseopts -E P:=apre p:=hpre S:=asuf s:=hsuf
    integer dirsuf=0
    if [[ -z $hsuf && "${${@//-default-/}% -# *}" == *-[[:alnum:]]#f* ]]; then
        dirsuf=1
    fi
    [[ -n $__hits ]] || return
    local dsuf dscr i full
    for i in {1..$#__hits}; do
        full=$IPREFIX$apre$hpre$__hits[$i]
        (( dirsuf )) && [[ $full != */ && -d ${~full} ]] && dsuf=/ || dsuf=
        (( $#__dscr >= i )) && dscr=${${${__dscr[$i]}##$__hits[$i] #}##-- #} || dscr=
        print -rn -- $'\x1e'"$IPREFIX$apre$hpre$__hits[$i]$dsuf$hsuf$asuf"$'\x1f'"$dscr"
    done
}
__qs_hist() {
    print -rn -- $'\x1d'
    local i
    fc -p
    [[ -r $__qs_histfile ]] && fc -R $__qs_histfile
    for (( i = HISTCMD; i > 0 && i > HISTCMD - 5000; i-- )); do
        [[ -n ${history[$i]} ]] && print -rn -- $'\x1e'"${history[$i]//$'\n'/\\n}"
    done
    fc -P
    print -rn -- $'\x1c'
}
print -r -- __QS_READY__
SETUP

export ZDOTDIR=$zdot
zpty -b z zsh -i || exit 1
await __QS_READY__ 20 || { print -u2 "zsh-complete: init failed"; exit 2 }

# Читаем всё от \x1d (или начала, если его нет) до \x1c
collect() {
    local chunk acc= deadline=$(( SECONDS + 5 ))
    while (( SECONDS < deadline )); do
        if zpty -r -t z chunk; then
            acc+=$chunk
            [[ $acc == *$'\x1c'* ]] && break
        else
            sleep 0.005
        fi
    done
    acc=${acc%%$'\x1c'*}
    [[ $acc == *$'\x1d'* ]] && acc=${acc#*$'\x1d'}
    REPLY=$acc
}

# Убираем escape-последовательности и управляющие символы
# (заодно никакой ^J/^M не дойдёт до ZLE как Enter)
setopt extendedglob
clean() {
    REPLY=${1//$'\e'\[[0-9;?]#[@-~]/}
    REPLY=${REPLY//[[:cntrl:]]/}
}

# Мусор перерисовки до первого элемента отбрасываем
items() {
    [[ $REPLY == *$'\x1e'* ]] && REPLY=${REPLY#*$'\x1e'} || REPLY=
}

complete() {
    local id=$1 buf item word desc
    clean $2; buf=$REPLY
    # ^U чистит строку от прошлого запроса, Tab — запускает дополнение
    zpty -w -n z $'\C-u'"$buf"$'\t'
    collect; items
    local -A seen=()
    for item in ${(ps:\x1e:)REPLY}; do
        word=${item%%$'\x1f'*}
        desc=${item#*$'\x1f'}
        [[ $desc == $item ]] && desc=
        clean $word; word=$REPLY
        clean $desc; desc=$REPLY
        [[ -z $word || -n ${seen[$word]} ]] && continue
        seen[$word]=1
        print -r -- "$id"$'\t'M$'\t'"$word"$'\t'"$desc"
    done
    print -r -- "$id"$'\t'E
    zpty -w -n z $'\C-u'
}

history_dump() {
    local item
    zpty -w -n z $'\C-u'
    zpty -w z " __qs_hist"
    collect; items
    for item in ${(ps:\x1e:)REPLY}; do
        clean $item
        [[ -n $REPLY && $REPLY != (\ |)__qs_hist ]] && print -r -- H$'\t'"$REPLY"
    done
    print -r -- H$'\t'E
}

while IFS= read -r req; do
    case $req in
    C*) complete "${${req#C}%%$'\t'*}" "${req#*$'\t'}" ;;
    H)  history_dump ;;
    esac
done
