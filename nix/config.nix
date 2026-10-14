# Папка конфига для ~/.config/quickshell: репо без флейка и прочего,
# что шеллу не нужно, и с подменёнными значениями из config/Settings.qml
{
  lib,
  runCommand,
  writeText,
  settings ? { },
}:

let
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference ../. (
      lib.fileset.unions (
        map lib.fileset.maybeMissing [
          ../flake.nix
          ../flake.lock
          ../nix
          ../.claude
          ../tests
          ../.qmlls.ini
          ../README.md
        ]
      )
    );
  };

  # Каждое значение в Settings.qml — одна строка
  #   readonly property <тип> <имя>: <значение>  // комментарий
  # Её хвост заменяем на JSON — это заодно и правильный литерал JS.
  # Пути (обои, например) toJSON сам кладёт в стор.
  lines = lib.splitString "\n" (builtins.readFile ../config/Settings.qml);
  match = name: line: builtins.match "( *readonly property [^ ]+ ${name}: ).*" line;
  known = name: lib.any (line: match name line != null) lines;
  unknown = lib.filter (name: !known name) (builtins.attrNames settings);

  patch =
    line:
    lib.foldl' (
      acc: name:
      let
        m = match name line;
      in
      if m == null then acc else builtins.head m + builtins.toJSON settings.${name}
    ) line (builtins.attrNames settings);

  settingsQml = writeText "Settings.qml" (lib.concatMapStringsSep "\n" patch lines);
in
if unknown != [ ] then
  throw "quickshell: в config/Settings.qml нет настроек ${lib.concatStringsSep ", " unknown}"
else
  runCommand "quickshell-config" { } (
    ''
      cp -r ${src} $out
    ''
    + lib.optionalString (settings != { }) ''
      chmod -R u+w $out
      cp ${settingsQml} $out/config/Settings.qml
    ''
  )
