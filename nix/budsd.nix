# Демон наушников (tools/budsd): шелл зовёт его по имени из PATH
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "budsd";
  version = "0.1.0";
  # Без target/ от локальной сборки
  src = lib.fileset.toSource {
    root = ../tools/budsd;
    fileset = lib.fileset.unions [
      ../tools/budsd/Cargo.toml
      ../tools/budsd/Cargo.lock
      ../tools/budsd/src
    ];
  };
  cargoLock.lockFile = ../tools/budsd/Cargo.lock;
  meta.mainProgram = "budsd";
}
