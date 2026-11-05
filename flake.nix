{
  description = "quickshell: бар, попауты, лаунчер и лок";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      homeModules.default = import ./nix/home.nix;
      homeManagerModules.default = self.homeModules.default;

      packages = forAll (pkgs: {
        # quickshell со всем, что нужно конфигу
        default = pkgs.callPackage ./nix/package.nix { };
        # сам конфиг, как он ляжет в ~/.config/quickshell
        config = pkgs.callPackage ./nix/config.nix { };
        # демон наушников для Bluetooth-попаута
        budsd = pkgs.callPackage ./nix/budsd.nix { };
        # QML-плагины: расширение плеера (MichaAI.Mpris) и logind
        mprisext = pkgs.callPackage ./nix/qmlplugin.nix {
          pname = "mprisext";
          uri = "MichaAI/Mpris";
        };
        logind = pkgs.callPackage ./nix/qmlplugin.nix {
          pname = "logind";
          uri = "MichaAI/Logind";
        };
      });

      formatter = forAll (pkgs: pkgs.nixfmt);
    };
}
