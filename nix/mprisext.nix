# QML-плагин MichaAI.Mpris (tools/mprisext): расширение плеера
# org.mpris.MediaPlayer2.MichaAIext по D-Bus. Кладётся в lib/qt-6/qml —
# package.nix добавляет его в QML_IMPORT_PATH шелла.
#
# Собирать тем же Qt, что и quickshell: плагин грузится в его процесс
{
  lib,
  rustPlatform,
  qt6,
}:

let
  # cxx-qt-build ищет модули Qt через qmake, а в nixpkgs каждый модуль —
  # свой путь в сторе: нужен qmake, который видит и QtQml
  qt = qt6.env "qt-mprisext-${qt6.qtbase.version}" [ qt6.qtdeclarative ];
  uri = "MichaAI/Mpris";
in
rustPlatform.buildRustPackage {
  pname = "mprisext";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../tools/mprisext;
    fileset = lib.fileset.unions [
      ../tools/mprisext/Cargo.toml
      ../tools/mprisext/Cargo.lock
      ../tools/mprisext/build.rs
      ../tools/mprisext/src
    ];
  };
  cargoLock.lockFile = ../tools/mprisext/Cargo.lock;

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
    cp $(find target -name libmprisext.so -path '*/release/*' | head -1) $dir/lib$plugin.so
    runHook postInstall
  '';

  doCheck = false;
}
