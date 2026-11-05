#!/usr/bin/env bash
# qmllint с модулями quickshell и Qt: tests/lint.sh [файлы.qml]
# (по умолчанию — все). Предупреждений быть не должно: дыры в типах
# Quickshell (PanelWindow корнем делегата, ObjectModel.values, anchor у
# PopupWindow, Bluetooth) заглушены на месте — // qmllint disable …
. "$(dirname "$0")/lib.sh"

qs=$(nix-store -q --references "$(readlink -f "$QST/quickshell")" | grep -- '-quickshell-[0-9]' | head -1)
imports=()
# QML-плагины на Rust (tools/mprisext, tools/qs-logind) — их кладёт в обёртку
# package.nix
mapfile -t plugins < <(nix-store -q --references "$(readlink -f "$QST/quickshell")" | grep -E -- '-(mprisext|qs-logind)-' || true)
for d in "$QST/qt6.qtdeclarative" "$qs" "$QST/qt6.qtquick3d" "$QST/qt6.qtquicktimeline" "${plugins[@]}"; do
    imports+=(-I "$(readlink -f "$d")/lib/qt-6/qml")
done

if [ $# -eq 0 ]; then
    mapfile -t files < <(git -C "$REPO" ls-files '*.qml' | sed "s|^|$REPO/|")
else
    files=()
    for f in "$@"; do files+=("$(realpath "$f")"); done
fi
# Пути — абсолютные: с относительным qmllint не находит qmldir файла и
# ругается на каждый синглтон («not declared as singleton in qmldir»).
# В выводе — снова от корня репозитория
set -o pipefail
qmllint "${imports[@]}" "${files[@]}" 2>&1 | sed "s|$REPO/||g"
