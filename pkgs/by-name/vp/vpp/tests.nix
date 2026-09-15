{
  lib,
  runCommand,
  vpp,
  libcbor,
  openssl,
}:
let
  minimal = vpp.override {
    plugins = [ ];
    drivers = [ ];
    cryptoEngines = [ ];
    tools = [ "vppctl" ];
    testTargets = [ ];
    withPython = false;
    withStackTraces = false;
    withOpenssl = false;
  };
  netlinkOnly = vpp.override {
    plugins = [
      "linux_cp"
      "linux_nl"
    ];
    excludedPlugins = [
      "dpdk"
      "linux_cp_unittest"
    ];
    drivers = [ ];
    cryptoEngines = [ ];
    testTargets = [ ];
    withPython = false;
    withStackTraces = false;
  };
  injected = minimal.override {
    extraBuildInputs = [ libcbor ];
    cmakeOptions.VPP_USE_LTO = false;
  };
  fails = args: !(builtins.tryEval ((vpp.override args).drvPath)).success;
  checks = {
    opensslCanBeDisabled =
      !(builtins.elem openssl
        (vpp.override {
          withOpenssl = false;
        }).buildInputs
      );
    pcapCanBeDisabled =
      !(builtins.elem "bpf_trace_filter"
        (vpp.override {
          withLibPcap = false;
        }).requiredFeatures.plugins
      );
    netlinkCanBeDisabled =
      lib.intersectLists [
        "linux_cp"
        "linux_nl"
        "linux_cp_unittest"
      ] (vpp.override { withNetlinkLibs = false; }).requiredFeatures.plugins == [ ];
    minimalHasNoOptionalLibraries = minimal.buildInputs == [ ];
    minimalHasNoPython = minimal.pythonBindings == null;
    minimalDisablesAllComponentGroups = lib.all (flag: builtins.elem flag minimal.cmakeFlags) [
      "-DVPP_PLUGINS:STRING=none"
      "-DVPP_DRIVERS:STRING=none"
      "-DVPP_CRYPTO_ENGINES:STRING=none"
      "-DVPP_TESTS:STRING=none"
    ];
    selectionInjectsOnlyNetlink =
      builtins.length netlinkOnly.buildInputs == 2
      &&
        netlinkOnly.requiredFeatures.plugins == [
          "linux_cp"
          "linux_nl"
        ];
    unavailableExclusionDoesNotReachCmake = builtins.elem "-DVPP_EXCLUDED_PLUGINS:STRING=linux_cp_unittest" netlinkOnly.cmakeFlags;
    extraDependencyIsInjected = injected.buildInputs == [ (lib.getDev libcbor) ];
    arbitraryCmakeOptionIsApplied = builtins.elem "-DVPP_USE_LTO:STRING=OFF" injected.cmakeFlags;
    missingMbedtlsIsRejected = fails { withMbedtls = true; };
    incompatibleMbedtlsIsRejected = fails {
      withMbedtls = true;
      mbedtlsPackage = openssl;
    };
    missingMusdkIsRejected = fails { withArmada = true; };
    missingRocIsRejected = fails {
      withOcteon = true;
      vppPlatform = "octeon10";
    };
    conflictingCmakeSelectionIsRejected = fails { cmakeOptions.VPP_PLUGINS = "dpdk"; };
    quiclyWithoutOpenSSLIsRejected = fails {
      withOpenssl = false;
      withQuicly = true;
    };
  };
  failures = builtins.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
assert lib.assertMsg (
  failures == [ ]
) "vpp option checks failed: ${lib.concatStringsSep ", " failures}";
runCommand "vpp-option-checks" { } ''
  touch "$out"
''
