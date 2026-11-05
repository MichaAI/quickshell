# QML-плагин на Rust из tools/<pname> (cxx-qt): MichaAI.Mpris — расширение
# плеера, MichaAI.Logind — logind. Кладётся в lib/qt-6/qml — package.nix
# добавляет его в QML_IMPORT_PATH шелла.
#
# Собирать тем же Qt, что и quickshell: плагин грузится в его процесс
{
  lib,
  rustPlatform,
  qt6,
  pname,
  uri,
}:

let
  # cxx-qt-build ищет модули Qt через qmake, а в nixpkgs каждый модуль —
  # свой путь в сторе: нужен qmake, который видит и QtQml
  qt = qt6.env "qt-${pname}-${qt6.qtbase.version}" [ qt6.qtdeclarative ];
  root = ../tools + "/${pname}";
in
rustPlatform.buildRustPackage {
  inherit pname;
  version = "0.1.0";
  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/Cargo.toml")
      (root + "/Cargo.lock")
      (root + "/build.rs")
      (root + "/src")
    ];
  };
  cargoLock.lockFile = root + "/Cargo.lock";

  nativeBuildInputs = [ qt ];
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
  ];
  dontWrapQtApps = true;
  # Хук qtbase выставляет свой QMAKE (без QtQml) — перебиваем перед сборкой
  preBuild = ''
    export QMAKE=${qt}/bin/qmake
  '';

  # cargo кладёт qmldir и plugin.qmltypes в OUT_DIR сборочного скрипта,
  # а библиотеку — в target: собираем из них модуль, как его ждёт Qt
  installPhase = ''
    runHook preInstall
    dir=$out/lib/qt-6/qml/${uri}
    mkdir -p $dir
    mod=$(find target -path '*/qt-build-utils/qml_modules/${uri}/qmldir' -printf '%h\n' | head -1)
    cp $mod/qmldir $mod/plugin.qmltypes $dir/
    plugin=$(sed -n 's/^\(optional \)\?plugin \([^ ]*\).*/\2/p' $dir/qmldir)
    cp $(find target -name lib${pname}.so -path '*/release/*' | head -1) $dir/lib$plugin.so
    runHook postInstall
  '';

  doCheck = false;
}
