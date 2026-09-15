{
  lib,
  nixos,
  runCommand,
  vpp,
}:
let
  evaluate =
    configuration:
    (nixos {
      system.stateVersion = "26.05";
      services.vpp = {
        enable = true;
      }
      // configuration;
    }).config;
  modern = evaluate {
    settings = {
      unix.cli-no-banner = true;
      cpu = {
        main-core = 0;
        extraConfig = "relative";
      };
      dpdk = {
        "dev 0000:01:00.0" = {
          num-rx-queues = 2;
          tso = "off";
        };
        no-pci = true;
        vdev = [
          "net_null0"
          "net_null1"
        ];
      };
    };
  };
  minimalPackage = vpp.override {
    plugins = [ ];
    drivers = [ ];
    cryptoEngines = [ ];
    withPython = false;
  };
  customized = evaluate {
    package = minimalPackage;
    settings = {
      unix.log = null;
      unix.cli-no-banner = false;
      plugins."plugin default".disable = true;
    };
  };
  badForeground = evaluate { settings.unix.nodaemon = false; };
  badInteractive = evaluate { settings.unix.interactive = true; };
  text = cfg: cfg.environment.etc."vpp/startup.conf".source.text;
  checks = {
    repeatedDirectivesArePreserved = lib.hasInfix "  vdev net_null0\n  vdev net_null1\n" (text modern);
    deviceBlockIsGenerated = lib.hasInfix "dev 0000:01:00.0 {\n" (text modern);
    blockExtraConfigIsAppended = lib.hasInfix "  main-core 0\n  relative\n}" (text modern);
    nullAndFalseAreOmitted =
      !(lib.hasInfix "  log " (text customized)) && !(lib.hasInfix "cli-no-banner" (text customized));
    packageSelectionIsRespected = lib.hasPrefix "${minimalPackage}/bin/vpp " customized.systemd.services.vpp.serviceConfig.ExecStart;
    defaultDoesNotConfigureDpdk = !(lib.hasInfix "dpdk {" (text (evaluate { })));
    runtimeDirectoryIsManaged = customized.systemd.services.vpp.serviceConfig.RuntimeDirectory == "vpp";
    logDirectoryIsManaged = customized.systemd.services.vpp.serviceConfig.LogsDirectory == "vpp";
    daemonizingIsRejected = lib.any (
      a: !a.assertion && lib.hasPrefix "services.vpp requires" a.message
    ) badForeground.assertions;
    interactiveIsRejected = lib.any (
      a: !a.assertion && lib.hasPrefix "services.vpp requires" a.message
    ) badInteractive.assertions;
  };
  failures = builtins.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
assert lib.assertMsg (
  failures == [ ]
) "VPP module checks failed: ${lib.concatStringsSep ", " failures}";
runCommand "vpp-module-checks" { } ''
  touch "$out"
''
