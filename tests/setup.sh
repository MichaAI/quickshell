#!/usr/bin/env bash
# Собрать всё для тестов в $QST (см. tests/qst.sh): quickshell из
# флейка этого репо и niri, sway, grim и прочее из nixpkgs. Повторный
# запуск почти мгновенный — всё уже в сторе.
#
# nixpkgs — тарболом с channels.nixos.org: из облачной сессии API GitHub,
# через который nix резолвит github:NixOS/nixpkgs, закрыт
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
. "$REPO/tests/qst.sh"
NIXPKGS=${NIXPKGS:-https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz}
mkdir -p "$QST"

if ! command -v nix >/dev/null; then
    [ -e /nix/var/nix/profiles/default/bin/nix ] || \
        curl -sSfL https://install.determinate.systems/nix | sh -s -- install linux --init none --no-confirm
    export PATH=/nix/var/nix/profiles/default/bin:$PATH
fi
nix() { command nix --extra-experimental-features "nix-command flakes" "$@"; }

echo "qs-test: quickshell из флейка" >&2
nix build "$REPO#default" --override-input nixpkgs "$NIXPKGS" --no-write-lock-file -o "$QST/quickshell"

# qt6.* — для qmllint (tests/lint.sh); mpv, playerctl, dbus — фейковые
# плееры на своей шине (tests/players.sh)
for p in niri sway grim mesa imagemagick wl-clipboard nerd-fonts.jetbrains-mono \
         qt6.qtdeclarative qt6.qtquick3d qt6.qtquicktimeline \
         mpv mpvScripts.mpris playerctl dbus; do
    echo "qs-test: $p" >&2
    nix build -f "$NIXPKGS" "$p" -o "$QST/$p"
done

# 3D-ава для тестов лока: лиса из образцов glTF, с анимациями
[ -s "$QST/Fox.glb" ] || curl -sSfL -o "$QST/Fox.glb" \
    https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Fox/glTF-Binary/Fox.glb \
    || echo "qs-test: Fox.glb не скачался — тест анимации авы будет пропущен" >&2

echo "qs-test: готово, $QST" >&2
