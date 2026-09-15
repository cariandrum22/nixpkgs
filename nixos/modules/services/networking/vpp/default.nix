{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.vpp;
  inherit (lib) mkOption types;
  format = import ./format.nix { inherit lib; };
  startupConf = pkgs.writeText "vpp-startup.conf" (format.render cfg.settings + cfg.extraConfig);
in
{
  imports = [ ./settings.nix ];

  meta.maintainers = [ lib.maintainers.cariandrum22 ];

  options.services.vpp = {
    enable = lib.mkEnableOption "VPP (Vector Packet Processor)";
    package = lib.mkPackageOption pkgs "vpp" { };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Additional VPP configuration appended to {file}`startup.conf`.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.settings.unix.nodaemon && !cfg.settings.unix.interactive;
        message = "services.vpp requires unix.nodaemon = true and unix.interactive = false for systemd supervision.";
      }
    ];

    environment.systemPackages = [ cfg.package ];
    environment.etc."vpp/startup.conf".source = startupConf;
    users.groups.vpp = { };

    systemd.services.vpp = {
      description = "Vector Packet Processor";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} -c ${startupConf}";
        Restart = "on-failure";
        RestartSec = "5s";
        RuntimeDirectory = "vpp";
        LogsDirectory = "vpp";
        LimitMEMLOCK = "infinity";
        PrivateTmp = true;
        ProtectSystem = true;
      };
    };
  };
}
