#!/usr/bin/env bash
# qmllint с модулями quickshell и Qt: tests/lint.sh [файлы.qml]
# (по умолчанию — все). В старом коде есть известные предупреждения
# (unqualified access и т. п.) — смотри, не добавилось ли новых
. "$(dirname "$0")/lib.sh"

qs=$(nix-store -q --references "$(readlink -f "$QST/quickshell")" | grep -- '-quickshell-[0-9]' | head -1)
imports=()
for d in "$QST/qt6.qtdeclarative" "$qs" "$QST/qt6.qtquick3d" "$QST/qt6.qtquicktimeline"; do
    imports+=(-I "$(readlink -f "$d")/lib/qt-6/qml")
done

cd "$REPO"
if [ $# -eq 0 ]; then mapfile -t files < <(git ls-files '*.qml'); else files=("$@"); fi
qmllint "${imports[@]}" "${files[@]}"
