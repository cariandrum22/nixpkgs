# Configurable VPP 26.06

`pkgs.vpp` accepts the following
package function arguments. Use `.override` on the registered package, or pass
them directly to `callPackage`. Dependencies are added for the selected features.
The default enables the supported Linux networking plugins and crypto engines,
including SASC, plus stack-trace demangling. Features needing unavailable or
incompatible libraries default to off. Optional developer tools such as G2 retain
their upstream opt-in defaults.

```nix
pkgs.vpp.override {
  withDpdk = false;
  withRdma = false;
  withPython = false;
  withSasc = true;
  cmakeOptions = {
    VPP_ENABLE_TRAJECTORY_TRACE = true;
    VPP_BUILD_VCL_TESTS = false;
    VPP_USE_LTO = false;
  };
}
```

## Feature flags and dependencies

| Argument | Default | VPP feature / dependency |
| --- | --- | --- |
| `withDpdk` | `true` | DPDK; nixpkgs DPDK with driver SDK headers enabled |
| `withAfXdp` | `true` | AF_XDP; nixpkgs xdp-tools and libbpf, linked dynamically |
| `enableAfXdpSkbMode` | `false` | Generic/SKB mode for AF_XDP |
| `withRdma` | `true` | RDMA; nixpkgs rdma-core, linked dynamically |
| `withLibPcap` | `true` | BPF trace filtering; libpcap |
| `withNetlinkLibs` | `true` | Linux control-plane plugins; libnl and libmnl |
| `withOpenssl` | `true` | OpenSSL-based VPP plugins and crypto engine |
| `withQuicly` | `withOpenssl` | Quicly QUIC engine; quicly, picotls, OpenSSL |
| `withPicotls` | `withOpenssl` | Picotls TLS engine; quicly version headers, picotls, OpenSSL |
| `withSrtp` | `true` | SRTP; nixpkgs srtp |
| `withSnort` | `true` | Snort integration and DAQ module; nixpkgs libdaq |
| `withSasc` | `true` | Session Aware Service Chaining; static, PIC nixpkgs libcbor without GCC LTO |
| `withIpsecMb` | x86_64 | Intel IPsec MB engine; nixpkgs intel-ipsec-mb with `SHARED=n` |
| `withStackTraces` | `true` | Stack traces; libunwind |
| `withDemangling` | `withStackTraces` | C++ symbol demangling; libiberty |
| `withPython` | `true` | Separately packaged Python API bindings |
| `withApiTests` | `true` | C/C++ VAPI test binaries; subunit and check |
| `withG2` | `false` | G2 event-log viewer; gtk2 |
| `withMbedtls` | `false` | Requires an injected `mbedtlsPackage` compatible with 2.x |
| `withArmada` | `false` | Requires an injected Marvell `musdk` |
| `withOcteon` | `false` | Requires `octeonRoc` and `vppPlatform = "octeon9"` or `"octeon10"` |
| `withNetmap` | `false` | FreeBSD-only upstream feature; rejected on Linux |

A flag controls that VPP feature. Another enabled feature can still require the
same library transitively (for example DPDK can depend on intel-ipsec-mb even
when the VPP IPsec MB engine is disabled). Snort integration does not install or
configure a Snort daemon. Its DAQ adapter uses libdaq headers; upstream prints
`LIBDAQ_LINK_LIBRARY-NOTFOUND` for the optional static archive but never links it.
API test binaries are built, but live integration tests
are not automatically run by the package build.

## Select individual components

`plugins`, `drivers`, `cryptoEngines`, `tools`, and `testTargets` accept lists of
upstream component names. `null` uses all available components; `[]` selects none.
`excludedPlugins` removes named plugins. Feature flags remain availability gates:
requesting a plugin whose feature is disabled fails instead of silently omitting it.
Dependencies for unselected feature groups are not injected.

```nix
pkgs.vpp.override {
  plugins = [ "quic" "quic_quicly" "tlspicotls" ];
  drivers = [];
  cryptoEngines = [ "native" "openssl" ];
  tools = [ "vppctl" ];
  testTargets = [];
  withPython = false;
}
```

Select and enable runtime dependencies between plugins as well: `quic_quicly`
needs `quic`, and `linux_nl` needs `linux_cp`. Upstream permits building
`linux_nl` alone, but loading it without `linux_cp` crashes during initialization.
The component lists select build outputs, not runtime startup configuration.
Upstream CMake rejects unknown names. The package additionally
checks that the selected dependency-backed features were actually configured.
Installed component lists are recorded in `nix-support/vpp-plugins`,
`nix-support/vpp-drivers`, and `nix-support/vpp-crypto-engines`.

Other upstream CMake settings are exposed by `cmakeOptions`, with boolean, string,
number, or list values. For example `VPP_BUILD_VCL`, `VPP_BUILD_VCL_BAPI`,
`VPP_BUILD_HS_SAPI_APPS`, `VPP_BUILD_VPPINFRA_TESTS`, `VPP_BUILD_PERFTOOL`,
`VPP_BUILD_MACTIME_TOP`, sanitizer, tracing, allocator, and CPU variant options can
be set there. Options managed by dedicated Nix arguments cannot be duplicated in
`cmakeOptions`. The Nix Python flag controls the separate Python package; CMake's
pip installation remains disabled. Extra build tools and libraries for advanced
CMake configurations can be supplied with `extraNativeBuildInputs` and
`extraBuildInputs`. These advanced configurations are not all validated by the
standard package build.

## Dependency injection and currently unavailable libraries

Ordinary dependency arguments (`dpdk`, `intel-ipsec-mb`, `libcbor`, `srtp`,
`libdaq`, `rdma-core`, `xdp-tools`, `libunwind`, `libiberty`, `openssl`, etc.) can
all be replaced through `.override`. The package retains nixpkgs source versions
and patches. It configures dependencies through their public function arguments:

| Package | Arguments used by VPP | Defaults for other consumers |
| --- | --- | --- |
| `dpdk` | `enableDriverSDK = true` | `false` |
| `intel-ipsec-mb` | `shared = false` | `true` |
| `libcbor` | `shared = false; enablePIC = true; enableLTO = false` | Shared unless the host platform is static; PIC/LTO default to `null`, preserving upstream's automatic settings |

When supplying replacements for these dependencies, preserve these argument
interfaces as well as the required headers and libraries.

No dependency `overrideAttrs` is needed. Disabling libcbor's GCC LTO makes its
archive usable by VPP's Clang linker; the build also
rejects unresolved libcbor symbols in the installed SASC plugin.

Calling the package with explicit arguments is equivalent to using `.override`:

```nix
pkgs.callPackage ./pkgs/by-name/vp/vpp/package.nix {
  withDpdk = false;
  withIpsecMb = true;
}
```

The path in this example is relative to the root of this nixpkgs checkout.

In this nixpkgs checkout:

- VPP-compatible quicly/picotls are not independently packaged. `quicly` defaults
  to the local `quicly/` recipe at `0.1.6-vpp`, which also provides picotls.
  `picotls` defaults to that same package. Both can be injected independently;
  the supplied builds must match VPP's expected headers and static archives.
- VPP 26.06 supports mbedTLS 2.x only. Nixpkgs removed `mbedtls_2` after its end
  of life; the available 3.x/4.x packages are incompatible. Enabling the feature
  requires an explicit compatible package, not merely `pkgs.mbedtls`.
- Marvell MUSDK and OCTEON ROC are not packaged. Their arguments default to
  `null`; enabling the corresponding driver without supplying them is an error.
  Building and using these drivers also requires the appropriate target platform
  and hardware. The validated target of this package is x86_64-linux.

```nix
pkgs.vpp.override {
  quicly = myVppCompatibleQuicly;
  picotls = myVppCompatiblePicotls;
  withMbedtls = true;
  mbedtlsPackage = myCompatibleMbedtls2;
}
```

`vppStdenv` selects the compiler environment (default: LLVM 18). `python3` selects
the Python used both for API generation and the optional bindings.

The Python library can also be used in an interpreter environment:

```nix
pkgs.python3.withPackages (_: [ pkgs.vpp.pythonBindings ])
```

## NixOS and validation

Use `services.vpp.package` to select the configured package. Its default remains
`pkgs.vpp`.

```nix
services.vpp = {
  enable = true;
  package = pkgs.vpp.override {
    withRdma = false;
  };
  settings = {
    unix.cli-listen = "/run/vpp/cli.sock";
    cpu = {
      main-core = 0;
      corelist-workers = "1-3";
    };
    dpdk."dev 0000:01:00.0".num-rx-queues = 3;
    socksvr.socket-name = "/run/vpp/api.sock";
  };
};
```

The module lives in `nixos/modules/services/networking/vpp/`:

- `default.nix` defines the service, package selection and systemd integration.
- `settings.nix` defines the structured configuration and documented defaults.
- `format.nix` defines VPP value types and renders blocks and directives.

Nested attribute sets produce blocks; true produces a bare flag; false/null
omit a directive; lists produce repeated directives. Use strings for values
such as `tso off`. Per-block and service-level `extraConfig` accept raw VPP
configuration. Settings must be supported by the selected VPP version and
plugins; configuration does not enable unavailable build features.

systemd manages `/run/vpp` and `/var/log/vpp` and runs VPP in the foreground.
The service runs as root for network/device access; the `vpp` group controls
socket access. Configure huge pages, NIC ownership and CPU placement for the
deployment hardware. The generated configuration is exposed at
`/etc/vpp/startup.conf`.

Build the package and expression-level option checks:

```sh
nix-build -A vpp -A vpp.tests.options -A vpp.tests.configuration
```

`nixosTests.vpp` exercises the unified package. VM execution needs KVM.

Validation of this 26.06 configuration on x86_64-linux:

- Default build: 104 plugins, 3 crypto engines, and 3 drivers. All installed
  shared libraries resolve their library dependencies. ACL, CNAT, QUIC/Quicly,
  Picotls, SRTP, Snort, and SASC load successfully; all three crypto engines
  register. Python API connection and `show_version` succeed.
- Minimal build with no plugins, crypto engines, drivers, or Python bindings:
  builds and starts successfully.
- Configuration generated by the NixOS module: starts and restarts VPP with
  the additional plugins and all three crypto engines. Python API connection
  and `show_version` succeed after both starts, without deleting shared memory
  between them. This checks the generated configuration outside systemd;
  running the NixOS VM test is still required to validate the complete service.
- Selection of `linux_cp` and `linux_nl`, with `linux_cp_unittest` excluded:
  builds and loads exactly those two plugins. Injecting OpenSSL separately with
  `withOpenssl = false` does not re-enable OpenSSL plugins or engines.
- Package option and NixOS configuration checks pass. The NixOS VM test evaluates;
  VM execution and hardware packet-processing tests require KVM and the target
  network hardware, which are unavailable in the build environment.
