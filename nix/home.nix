# Модуль home-manager: michaai.quickshell
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.michaai.quickshell;
  inherit (lib) mkOption mkEnableOption types;

  configDir = pkgs.callPackage ./config.nix { inherit (cfg) settings; };
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "michaai" "quickshell" "weatherLocation" ]
      [ "michaai" "quickshell" "weather" "location" ]
    )
  ];

  options.michaai.quickshell = {
    enable = mkEnableOption "quickshell с баром, лаунчером и локом";

    package = mkOption {
      type = types.package;
      default = pkgs.quickshell;
      defaultText = lib.literalExpression "pkgs.quickshell";
      description = "Сам quickshell. Его обернут: см. finalPackage.";
    };

    finalPackage = mkOption {
      type = types.package;
      readOnly = true;
      description = "quickshell с утилитами в PATH и QtQuick3D для 3D-авы.";
    };

    runtimeInputs = mkOption {
      type = types.listOf types.package;
      default = with pkgs; [
        brightnessctl
        bubblewrap
        cava
        cliphist
        coreutils
        curl
        fd
        findutils
        libqalculate
        procps
        slurp # скриншот области под driftwm
        util-linux
        wl-clipboard
        xdg-utils
        zsh
        (callPackage ./budsd.nix { })
      ];
      defaultText = lib.literalMD "утилиты, которые зовут бар, лаунчер и лок";
      description = "Что положить в PATH шеллу. Композитор и терминал — свои, их тут нет.";
    };

    avatar3d = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Дать шеллу QtQuick3D, QtQuick.Timeline и balsam: без них лок
        показывает обычную ~/.face вместо 3D-модели.
      '';
    };

    weather = {
      location = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "Москва";
        description = ''
          Город для погоды на баре или координаты "широта,долгота".
          null — определить по IP.
        '';
      };

      provider = mkOption {
        type = types.nullOr (types.enum [ "metno" "openmeteo" "wttr" ]);
        default = null;
        description = ''
          Откуда брать прогноз: met.no, Open-Meteo или wttr.in (только 3 дня).
          null — met.no.
        '';
      };

      proxy = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "socks5h://127.0.0.1:1080";
        description = ''
          Прокси для запросов погоды в формате curl -x. Ляжет в стор открытым
          текстом — логин и пароль сюда лучше не класть.
        '';
      };
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      example = lib.literalExpression ''
        {
          terminal = [ "foot" ];
          lockWallpaper = ./wall.png;
          lockAnimation = "Run";
        }
      '';
      description = ''
        Значения из config/Settings.qml, которые надо заменить. Имена —
        как в файле; неизвестное имя — ошибка сборки.
      '';
    };

    avatar = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = lib.literalExpression "./Fox.glb";
      description = ''
        3D-модель для лока (.glb/.gltf/.fbx/.obj). Ляжет в ~/avatar.<расширение>,
        откуда её берёт лок. Какую анимацию играть — settings.lockAnimation.
      '';
    };

    liveSource = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/micha/dots/quickshell";
      description = ''
        Абсолютный путь к рабочей копии репо. Тогда ~/.config/quickshell —
        ссылка прямо на неё, мимо стора: правки подхватываются на лету.
        settings при этом не применить — их место в самом Settings.qml.
      '';
    };

    systemd = {
      enable = mkEnableOption "запуск шелла пользовательским сервисом systemd";

      target = mkOption {
        type = types.str;
        default = "graphical-session.target";
        description = "С каким таргетом запускать и останавливать шелл.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.liveSource == null || cfg.settings == { };
        message = "michaai.quickshell: settings не применяются вместе с liveSource — правь Settings.qml в рабочей копии";
      }
    ];

    michaai.quickshell.finalPackage = pkgs.callPackage ./package.nix {
      quickshell = cfg.package;
      inherit (cfg) runtimeInputs;
      with3d = cfg.avatar3d;
      # Через окружение, а не settings: так работает и с liveSource
      env = lib.filterAttrs (_: v: v != null) {
        QS_WEATHER_LOCATION = cfg.weather.location;
        QS_WEATHER_PROVIDER = cfg.weather.provider;
        QS_WEATHER_PROXY = cfg.weather.proxy;
      };
    };

    home.packages = [ cfg.finalPackage ];

    xdg.configFile."quickshell".source =
      if cfg.liveSource != null then config.lib.file.mkOutOfStoreSymlink cfg.liveSource else configDir;

    home.file = lib.mkIf (cfg.avatar != null) {
      # Имя файла не может ссылаться на стор, а у модели из fetchurl или
      # "${inputs.…}/…" ссылка есть — от расширения берём только текст
      "avatar.${lib.last (lib.splitString "." (builtins.unsafeDiscardStringContext (baseNameOf cfg.avatar)))}".source =
        cfg.avatar;
    };

    systemd.user.services.quickshell = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "quickshell";
        PartOf = [ cfg.systemd.target ];
        After = [ cfg.systemd.target ];
        # Из стора шелл правки файлов не увидит: перезапускаем его,
        # когда home-manager выкатывает новый конфиг
        X-Restart-Triggers = lib.optional (cfg.liveSource == null) "${configDir}";
      };
      Service = {
        ExecStart = lib.getExe' cfg.finalPackage "quickshell";
        Restart = "on-failure";
      };
      Install.WantedBy = [ cfg.systemd.target ];
    };
  };
}
