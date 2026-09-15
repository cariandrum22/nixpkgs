{ lib, ... }:
let
  inherit (lib) mkOption types;
  format = import ./format.nix { inherit lib; };
  inherit (format) valueType sectionType;
in
{
  options.services.vpp.settings = mkOption {
    type = types.submodule {
      freeformType = format.type;
      options = {
        unix = mkOption {
          default = { };
          description = "Unix process and CLI settings.";
          type = types.submodule {
            freeformType = types.attrsOf valueType;
            options = {
              nodaemon = mkOption {
                type = types.bool;
                default = true;
                description = "Run in the foreground so systemd can supervise VPP.";
              };
              interactive = mkOption {
                type = types.bool;
                default = false;
                description = "Attach the CLI to standard input; unsuitable for the system service.";
              };
              cli-listen = mkOption {
                type = types.nullOr types.str;
                default = "/run/vpp/cli.sock";
                description = "Unix socket path or address on which the VPP CLI listens.";
              };
              log = mkOption {
                type = types.nullOr types.str;
                default = "/var/log/vpp/vpp.log";
                description = "VPP log file. Set to null to omit file logging.";
              };
              gid = mkOption {
                type = types.nullOr types.str;
                default = "vpp";
                description = "Group owning VPP sockets. Members can control VPP.";
              };
            };
          };
        };
        dpdk = mkOption {
          type = sectionType;
          default = null;
          description = "DPDK settings. Device blocks use keys such as `dev 0000:01:00.0`.";
        };
        cpu = mkOption {
          type = sectionType;
          default = null;
          description = "CPU affinity, worker and scheduler settings.";
        };
      };
    };
    default = { };
    example = lib.literalExpression ''
      {
        cpu = {
          main-core = 0;
          corelist-workers = "1-3";
        };
        dpdk."dev 0000:01:00.0".num-rx-queues = 3;
        plugins."plugin default".disable = true;
        plugins."plugin dpdk_plugin.so".enable = true;
        socksvr.socket-name = "/run/vpp/api.sock";
      }
    '';
    description = ''
      Settings for {file}`startup.conf`, using VPP's directive names.
      Attribute sets generate blocks, true generates a bare directive, and
      false or null omits a directive. Lists repeat the same directive.
      Strings and numbers are emitted verbatim; use strings such as "on"
      or "off" for directives requiring a value rather than a bare flag.
      An `extraConfig` string inside a block appends raw VPP configuration.
      Plugin availability depends on the selected package's build options.
    '';
  };
}
