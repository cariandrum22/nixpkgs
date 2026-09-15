{
  lib,
  llvmPackages_18,
  nix-update-script,
  fetchFromGitHub,
  callPackage,
  cmake,
  pkg-config,
  python3,
  nixosTests,
  dpdk,
  intel-ipsec-mb,
  xdp-tools,
  libbpf,
  libmnl,
  elfutils,
  zlib,
  zstd,
  rdma-core,
  openssl,
  libpcap,
  jansson,
  libnl,
  libdaq,
  srtp,
  libcbor,
  libunwind,
  libiberty,
  subunit,
  check,
  gtk2,
  vppStdenv ? llvmPackages_18.stdenv,
  quicly ? callPackage ./quicly { inherit openssl; },
  picotls ? quicly,
  mbedtlsPackage ? null,
  musdk ? null,
  octeonRoc ? null,
  # null selects all available components; [] selects none.
  plugins ? null,
  excludedPlugins ? [ ],
  drivers ? null,
  cryptoEngines ? null,
  tools ? null,
  testTargets ? null,
  withDpdk ? true,
  withAfXdp ? true,
  withRdma ? true,
  withOpenssl ? true,
  withLibPcap ? true,
  withNetlinkLibs ? true,
  withQuicly ? withOpenssl,
  withPicotls ? withOpenssl,
  withSrtp ? true,
  withSnort ? true,
  withSasc ? true,
  withIpsecMb ? vppStdenv.hostPlatform.isx86_64,
  withMbedtls ? false,
  withArmada ? false,
  withOcteon ? false,
  withNetmap ? false,
  withPython ? true,
  withStackTraces ? true,
  withDemangling ? withStackTraces,
  withApiTests ? true,
  withG2 ? false,
  vppPlatform ? "default",
  enableAfXdpSkbMode ? false,
  # Other upstream CMake options, e.g. VPP_BUILD_VCL or VPP_USE_LTO.
  cmakeOptions ? { },
  extraBuildInputs ? [ ],
  extraNativeBuildInputs ? [ ],
}:
let
  buildStdenv = vppStdenv;
  version = "26.06";
  python = python3.withPackages (ps: [ ps.ply ]);
  selected = names: name: names == null || builtins.elem name names;
  pluginSelected = name: selected plugins name && !(builtins.elem name excludedPlugins);
  selection =
    names:
    if names == null then
      ""
    else if names == [ ] then
      "none"
    else
      lib.concatStringsSep "," names;

  # Configure dependencies through their public package arguments.
  dpdkForVpp = dpdk.override { enableDriverSDK = true; };
  ipsecMbForVpp = intel-ipsec-mb.override { shared = false; };
  libcborForVpp = libcbor.override {
    shared = false;
    enablePIC = true;
    # GCC LTO archives cannot be consumed by VPP's Clang linker.
    enableLTO = false;
  };

  # Each group controls both dependency injection and source discovery. Skipping
  # discovery prevents transitive dependencies from re-enabling disabled features.
  feature = enable: dirs: pluginNames: engineNames: driverNames: inputs: {
    inherit dirs inputs;
    allPlugins = pluginNames;
    plugins = lib.filter pluginSelected pluginNames;
    engines = lib.filter (selected cryptoEngines) engineNames;
    drivers = lib.filter (selected drivers) driverNames;
    enabled =
      enable
      && (
        lib.any pluginSelected pluginNames
        || lib.any (selected cryptoEngines) engineNames
        || lib.any (selected drivers) driverNames
      );
  };
  features = [
    (feature withDpdk [ "plugins/dpdk" ] [ "dpdk" ] [ ] [ ] [ dpdkForVpp jansson elfutils zlib zstd ])
    (feature withAfXdp [
      "plugins/af_xdp"
    ] [ "af_xdp" ] [ ] [ ] [ xdp-tools libbpf elfutils zlib zstd ])
    (feature withRdma [ "plugins/rdma" ] [ "rdma" ] [ ] [ ] [ rdma-core ])
    (feature withLibPcap [ "plugins/bpf_trace_filter" ] [ "bpf_trace_filter" ] [ ] [ ] [ libpcap ])
    (feature withNetlinkLibs [
      "plugins/linux-cp"
    ] [ "linux_cp" "linux_nl" "linux_cp_unittest" ] [ ] [ ] [ libnl libmnl ])
    (feature withOpenssl [
      "plugins/ikev2"
      "plugins/lisp"
      "plugins/quic"
      "plugins/tlsopenssl"
      "plugins/wireguard"
    ] [ "ikev2" "lisp" "lisp_unittest" "quic" "tlsopenssl" "wireguard" ] [ ] [ ] [ openssl ])
    (feature withOpenssl [ "crypto_engines/openssl" ] [ ] [ "openssl" ] [ ] [ openssl ])
    (feature withQuicly [ "plugins/quic_quicly" ] [ "quic_quicly" ] [ ] [ ] [ quicly picotls openssl ])
    (feature withPicotls [ "plugins/tlspicotls" ] [ "tlspicotls" ] [ ] [ ] [ quicly picotls openssl ])
    (feature withSrtp [ "plugins/srtp" ] [ "srtp" ] [ ] [ ] [ srtp ])
    (feature withSnort [ "plugins/snort" ] [ "snort" ] [ ] [ ] [ libdaq ])
    (feature withSasc [ "plugins/sasc" ] [ "sasc" ] [ ] [ ] [ libcborForVpp ])
    (feature withIpsecMb [ "crypto_engines/ipsecmb" ] [ ] [ "ipsecmb" ] [ ] [ ipsecMbForVpp ])
    (feature withMbedtls [ "plugins/tlsmbedtls" ] [ "tlsmbedtls" ] [ ] [ ] [ mbedtlsPackage ])
    (feature withArmada [ "drivers/armada" ] [ ] [ ] [ "armada" ] [ musdk ])
    (feature withOcteon [ "drivers/octeon" ] [ ] [ ] [ "octeon" ] [ octeonRoc ])
    (feature withNetmap [ "plugins/netmap" ] [ "netmap" ] [ ] [ ] [ ])
  ];
  activeFeatures = lib.filter (f: f.enabled) features;
  disabledDirs = lib.concatMap (f: f.dirs) (lib.filter (f: !f.enabled) features);
  unavailablePlugins = lib.concatMap (f: f.allPlugins) (lib.filter (f: !f.enabled) features);
  requiredPlugins = lib.concatMap (f: f.plugins) activeFeatures;
  requiredEngines = lib.concatMap (f: f.engines) activeFeatures;
  requiredDrivers = lib.concatMap (f: f.drivers) activeFeatures;
  apiTestsEnabled =
    withApiTests
    && lib.any (selected testTargets) [
      "vapi_c_test"
      "vapi_cpp_test"
    ];
  g2Enabled = withG2 && selected tools "g2";

  managedOptions = {
    VPP_PLATFORM = vppPlatform;
    VPP_PLUGINS = selection (if plugins == null then null else lib.filter pluginSelected plugins);
    VPP_EXCLUDED_PLUGINS = lib.concatStringsSep "," (
      lib.subtractLists unavailablePlugins excludedPlugins
    );
    VPP_DRIVERS = selection drivers;
    VPP_CRYPTO_ENGINES = selection cryptoEngines;
    VPP_TOOLS = selection tools;
    VPP_TESTS = selection testTargets;
    VPP_USE_SYSTEM_DPDK = true;
    VPP_BUILD_PYTHON_API = false; # Packaged separately, without invoking pip from CMake.
    VPP_BUILD_G2 = g2Enabled;
    CMAKE_DISABLE_FIND_PACKAGE_OpenSSL = !withOpenssl;
  };
  cmakeValue =
    value:
    if builtins.isBool value then
      (if value then "ON" else "OFF")
    else if builtins.isList value then
      lib.concatMapStringsSep ";" toString value
    else
      toString value;
  options = {
    CMAKE_BUILD_TYPE = "Release";
    VPP_LIBRARY_DIR = "lib";
    VPP_USE_CCACHE = false;
    Python3_EXECUTABLE = "${python}/bin/python3";
    CMAKE_INSTALL_RPATH_USE_LINK_PATH = true;
  }
  // managedOptions
  // cmakeOptions;

  src = fetchFromGitHub {
    owner = "FDio";
    repo = "vpp";
    tag = "v${version}";
    hash = "sha256-pYqDa1PA4GX+sk3gNR87lhsyKSVsqIA3NeEWVQPvubM=";
  };
  vpp-papi = python3.pkgs.buildPythonPackage {
    pname = "vpp-papi";
    inherit version src;
    sourceRoot = "${src.name}/src/vpp-api/python";
    pyproject = true;
    build-system = [ python3.pkgs.setuptools ];
    postPatch = ''
      substituteInPlace setup.py --replace-fail 'version="2.3.2"' 'version="${version}"'
    '';
    doCheck = false; # Integration tests require a running VPP instance.
    pythonImportsCheck = [ "vpp_papi" ];
    meta = {
      description = "VPP Python API bindings";
      homepage = "https://fd.io/";
      license = lib.licenses.asl20;
      maintainers = with lib.maintainers; [
        maevii
        cariandrum22
      ];
    };
  };
  requireComponents =
    kind: names:
    lib.concatMapStrings (name: ''
      if ! grep -Fx -- ${lib.escapeShellArg name} nix-vpp-${kind} >/dev/null; then
        echo ${lib.escapeShellArg "Requested VPP ${kind} component '${name}' was not built; check its dependencies."} >&2
        exit 1
      fi
    '') names;
  vpp-core = buildStdenv.mkDerivation (finalAttrs: {
    pname = "vpp";
    inherit version src;
    sourceRoot = "${finalAttrs.src.name}/src";
    patches = [
      ./0001-explicity-include-std-array.patch
      ./cnat-initialize-port-counters.patch
      ./use-dynamic-libs.patch
      ./cmake-plugin-selection.patch
    ]
    ++ lib.optional enableAfXdpSkbMode ./xdp-skb-mode.patch;
    strictDeps = true;
    nativeBuildInputs = [
      cmake
      pkg-config
      python
    ]
    ++ extraNativeBuildInputs;
    buildInputs =
      lib.unique (lib.concatMap (f: f.inputs) activeFeatures)
      ++ lib.optional withStackTraces libunwind
      ++ lib.optional withDemangling libiberty
      ++ lib.optionals apiTestsEnabled [
        subunit
        check
      ]
      ++ lib.optional g2Enabled gtk2
      ++ extraBuildInputs;
    hardeningDisable = [
      "fortify"
      "bindnow"
    ];
    enableParallelBuilding = true;
    env.VPP_BUILD_HOST = "nixpkgs";
    cmakeFlags = lib.mapAttrsToList (name: value: lib.cmakeFeature name (cmakeValue value)) options;
    postPatch = ''
      patchShebangs scripts tools vpp-api
      substituteInPlace CMakeLists.txt --replace-fail "    pkg" ""
      for dir in ${lib.escapeShellArgs disabledDirs}; do
        printf 'return()\n' > "$dir/CMakeLists.txt"
      done
      # Record the actual configured components, not just the requested flags.
      cat >> CMakeLists.txt <<'CMAKE'
      foreach(kind PLUGINS CRYPTO_ENGINES DRIVERS)
        string(TOLOWER "''${kind}" lower_kind)
        string(REPLACE "_" "-" lower_kind "''${lower_kind}")
        string(REPLACE ";" "\n" components "''${VPP_''${kind}_LIST}")
        file(WRITE "''${CMAKE_BINARY_DIR}/nix-vpp-''${lower_kind}" "''${components}\n")
      endforeach()
      CMAKE
    ''
    + lib.optionalString (!withStackTraces) ''
      substituteInPlace vppinfra/CMakeLists.txt \
        --replace-fail 'vpp_find_path(LIBUNWIND_INCLUDE_DIR unwind.h)' 'set(LIBUNWIND_INCLUDE_DIR "")' \
        --replace-fail 'vpp_find_library(LIBUNWIND_LIB NAMES unwind libunwind)' 'set(LIBUNWIND_LIB "")'
    ''
    + lib.optionalString (!withDemangling) ''
      substituteInPlace vlib/CMakeLists.txt \
        --replace-fail 'vpp_find_path(LIBIBERTY_INCLUDE_DIR libiberty/demangle.h)' 'set(LIBIBERTY_INCLUDE_DIR "")' \
        --replace-fail 'vpp_find_library(LIBIBERTY_LIB NAMES iberty libiberty)' 'set(LIBIBERTY_LIB "")'
    ''
    + lib.optionalString (!apiTestsEnabled) ''
      substituteInPlace vpp-api/vapi/CMakeLists.txt \
        --replace-fail 'vpp_find_path(SUBUNIT_INCLUDE_DIR NAMES subunit/child.h)' 'set(SUBUNIT_INCLUDE_DIR "")' \
        --replace-fail 'vpp_find_library(SUBUNIT_LIB NAMES subunit)' 'set(SUBUNIT_LIB "")'
    '';
    preConfigure = ''
      echo "${version}-nixos" > scripts/.version
    '';
    postConfigure =
      requireComponents "plugins" requiredPlugins
      + requireComponents "crypto-engines" requiredEngines
      + requireComponents "drivers" requiredDrivers;
    # Upstream API targets share outputs; finish these before parallel compilation.
    preBuild = ''
      cmake --build . --target api_headers --parallel 1
    '';
    postInstall =
      lib.optionalString withPython ''
        mkdir -p "$out/${python3.sitePackages}"
        cp -rs ${vpp-papi}/${python3.sitePackages}/. "$out/${python3.sitePackages}/"
      ''
      + ''
        for kind in plugins crypto-engines drivers; do
          install -Dm644 "nix-vpp-$kind" "$out/nix-support/vpp-$kind"
        done
      ''
      + lib.optionalString (withSasc && pluginSelected "sasc") ''
        # A shared plugin can link successfully with unresolved symbols even when
        # its static dependency was ignored. Catch this before runtime loading.
        if ${buildStdenv.cc.targetPrefix}nm -D --undefined-only "$out/lib/vpp_plugins/sasc_plugin.so" \
          | grep -E '[[:space:]]cbor_[[:alnum:]_]+$'; then
          echo "SASC has unresolved libcbor symbols; check static archive compatibility." >&2
          exit 1
        fi
      '';
    passthru = {
      pythonBindings = if withPython then vpp-papi else null;
      requiredFeatures = {
        plugins = requiredPlugins;
        cryptoEngines = requiredEngines;
        drivers = requiredDrivers;
      };
      updateScript = nix-update-script { };
      tests = {
        vpp = nixosTests.vpp;
        options = callPackage ./tests.nix { };
        configuration = callPackage ./module-tests.nix { };
      };
    };
    meta = {
      description = "Vector Packet Processor with selectable plugins and Python API bindings";
      homepage = "https://s3-docs.fd.io/vpp/${version}/";
      license = lib.licenses.asl20;
      maintainers = with lib.maintainers; [
        maevii
        cariandrum22
      ];
      mainProgram = "vpp";
      platforms = lib.platforms.linux;
    };
  });
in
assert lib.assertMsg
  (lib.intersectLists (builtins.attrNames managedOptions) (builtins.attrNames cmakeOptions) == [ ])
  "vpp: use the dedicated Nix arguments for plugin, driver, engine, tool, test, Python, G2 and OpenSSL selection.";
assert lib.assertMsg (
  !(withQuicly || withPicotls) || withOpenssl
) "vpp: quicly/picotls require withOpenssl.";
assert lib.assertMsg (
  !withDemangling || withStackTraces
) "vpp: withDemangling requires withStackTraces.";
assert lib.assertMsg
  (
    !withMbedtls
    || (
      mbedtlsPackage != null
      && lib.versionAtLeast (mbedtlsPackage.version or "0") "2"
      && lib.versionOlder (mbedtlsPackage.version or "3") "3"
    )
  )
  "vpp: withMbedtls requires an injected mbedtlsPackage compatible with mbedTLS 2.x; nixpkgs mbedTLS 3.x/4.x is not supported by VPP 26.06.";
assert lib.assertMsg (
  !withArmada || musdk != null
) "vpp: withArmada requires an injected musdk package.";
assert lib.assertMsg (
  !withOcteon
  || (
    octeonRoc != null
    && builtins.elem vppPlatform [
      "octeon9"
      "octeon10"
    ]
  )
) "vpp: withOcteon requires octeonRoc and vppPlatform = octeon9 or octeon10.";
assert lib.assertMsg (
  !withNetmap || buildStdenv.hostPlatform.isFreeBSD
) "vpp: Netmap is only supported on FreeBSD.";
assert lib.assertMsg (
  !withIpsecMb || buildStdenv.hostPlatform.isx86_64
) "vpp: Intel IPsec MB requires x86_64.";
assert lib.assertMsg (
  !enableAfXdpSkbMode || withAfXdp
) "vpp: enableAfXdpSkbMode requires withAfXdp.";
vpp-core
