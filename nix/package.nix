# quickshell, которому видно всё, что зовёт конфиг: утилиты в PATH,
# плагины картинок для обоев (webp и т.п.) и, для 3D-авы на локе,
# QtQuick3D с QtQuick.Timeline и balsam. Сам qs тоже в PATH: конфиг зовёт
# его через Process
{
  lib,
  symlinkJoin,
  makeWrapper,
  quickshell,
  qt6,
  runtimeInputs ? [ ],
  with3d ? true,
  # Переменные окружения шелла, например QS_WEATHER_LOCATION
  env ? { },
}:

let
  qml = lib.optionals with3d [
    qt6.qtquick3d
    qt6.qtquicktimeline
  ];
  plugins = [ qt6.qtimageformats ] ++ qml;
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
        --prefix QT_PLUGIN_PATH : ${lib.makeSearchPath qt6.qtbase.qtPluginPrefix plugins} \
        ${lib.optionalString with3d ''
          --prefix QML_IMPORT_PATH : ${lib.makeSearchPath qt6.qtbase.qtQmlPrefix qml}
        ''} \
        ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v}") env)}
    done
  '';

  inherit (quickshell) meta;
}
