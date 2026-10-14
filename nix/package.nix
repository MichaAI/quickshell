# quickshell, которому видно всё, что зовёт конфиг: утилиты в PATH и, для
# 3D-авы на локе, QtQuick3D с QtQuick.Timeline и balsam. Сам qs тоже в
# PATH: конфиг зовёт его через Process
{
  lib,
  symlinkJoin,
  makeWrapper,
  quickshell,
  qt6,
  runtimeInputs ? [ ],
  with3d ? true,
}:

let
  qml = lib.optionals with3d [
    qt6.qtquick3d
    qt6.qtquicktimeline
  ];
in
symlinkJoin {
  name = "quickshell-wrapped-${quickshell.version}";
  paths = [ quickshell ];
  nativeBuildInputs = [ makeWrapper ];

  postBuild = ''
    for bin in $out/bin/*; do
      wrapProgram "$bin" \
        --prefix PATH : $out/bin \
        --prefix PATH : ${lib.makeBinPath (runtimeInputs ++ lib.optional with3d qt6.qtquick3d)} \
        ${lib.optionalString with3d ''
          --prefix QML_IMPORT_PATH : ${lib.makeSearchPath qt6.qtbase.qtQmlPrefix qml} \
          --prefix QT_PLUGIN_PATH : ${lib.makeSearchPath qt6.qtbase.qtPluginPrefix qml}
        ''}
    done
  '';

  inherit (quickshell) meta;
}
