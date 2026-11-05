# quickshell, которому видно всё, что зовёт конфиг: утилиты в PATH,
# плагины картинок для обоев (webp и т.п.) и, для 3D-авы на локе,
# QtQuick3D с QtQuick.Timeline и balsam. Сам qs тоже в PATH: конфиг зовёт
# его через Process. И QML-плагины на Rust — MichaAI.Mpris (расширение
# плеера) и MichaAI.Logind — тем же Qt, что и quickshell
{
  lib,
  callPackage,
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
  qml3d = lib.optionals with3d [
    qt6.qtquick3d
    qt6.qtquicktimeline
  ];
  plugin = pname: uri: callPackage ./qmlplugin.nix { inherit qt6 pname uri; };
  qml = [
    (plugin "mprisext" "MichaAI/Mpris")
    (plugin "qs-logind" "MichaAI/Logind")
  ]
  ++ qml3d;
  plugins = [ qt6.qtimageformats ] ++ qml3d;
in
symlinkJoin {
  name = "quickshell-wrapped-${quickshell.version}";
  paths = [ quickshell ];
  nativeBuildInputs = [ makeWrapper ];

  # Аргументы wrapProgram списком: так пустые и необязательные куски
  # не рвут перенос строки в команде
  postBuild =
    let
      args =
        [
          "--prefix PATH : $out/bin"
          "--prefix PATH : ${lib.makeBinPath (runtimeInputs ++ lib.optional with3d qt6.qtquick3d)}"
          "--prefix QT_PLUGIN_PATH : ${lib.makeSearchPath qt6.qtbase.qtPluginPrefix plugins}"
        ]
        ++ [ "--prefix QML_IMPORT_PATH : ${lib.makeSearchPath qt6.qtbase.qtQmlPrefix qml}" ]
        ++ lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v}") env;
    in
    ''
      for bin in $out/bin/*; do
        wrapProgram "$bin" ${lib.concatStringsSep " " args}
      done
    '';

  inherit (quickshell) meta;
}
