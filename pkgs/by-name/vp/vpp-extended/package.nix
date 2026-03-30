{
  lib,
  llvmPackages_18,
  fetchgit,
  fetchurl,
  callPackage,
  cmake,
  dpdk,
  intel-ipsec-mb,
  xdp-tools,
  libbpf,
  libmnl,
  elfutils,
  zlib,
  rdma-core,
  python313,
  python313Packages,
  openssl,
  libuuid,
  subunit,
  pkg-config,
  libpcap,
  jansson,
  libnl,
  libdaq,
  srtp,
  check,
  nixosTests,
  libunwind,
  symlinkJoin,
  buildPythonPackage ? python313Packages.buildPythonPackage,
  setuptools ? python313Packages.setuptools,
}:

let
  stdenv = llvmPackages_18.stdenv;

  xdp-tools' = xdp-tools.overrideAttrs (old: {
    postInstall = ''
      # Drop unfortunate references to glibc.dev/include at least from $lib
      nuke-refs "$lib"/lib/bpf/*.o
    '';
  });

  # VPP links against the static archive from intel-ipsec-mb.
  intel-ipsec-mb' = intel-ipsec-mb.overrideAttrs (old: {
    makeFlags = old.makeFlags ++ [
      "SHARED=n"
    ];
  });

  dpdk' = dpdk.overrideAttrs (old: rec {
    version = "25.11";
    src = fetchurl {
      url = "https://fast.dpdk.org/rel/dpdk-${version}.tar.xz";
      sha256 = "sha256-UukNKlMe897QKDvZGryUmAaY8fZHH6CWWKAhfPZglSY=";
    };
    mesonFlags = old.mesonFlags ++ [
      "-Denable_driver_sdk=true"
    ];
  });

  rdma-core' = rdma-core.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [
      "-DENABLE_STATIC=1"
    ];
  });

  srtp' = srtp.overrideAttrs (old: {
    mesonFlags = old.mesonFlags ++ [
      "-Ddefault_library=static"
    ];
  });

  # VPP source
  vppSrc = fetchgit {
    url = "https://gerrit.fd.io/r/vpp";
    rev = "refs/tags/v${version}";
    sha256 = "sha256-z9yh1ZMP28SSzHNBdO7UnvVqsIqtXUcwYZUH1UdBUB0=";
  };

  version = "26.02";

  # Python API package
  vpp-papi = buildPythonPackage {
    pname = "vpp-papi";
    inherit version;

    src = vppSrc;
    sourceRoot = "vpp/src/vpp-api/python";

    pyproject = true;

    build-system = [ setuptools ];

    # No external dependencies required
    dependencies = [ ];

    # Skip tests as they require running VPP
    doCheck = false;

    pythonImportsCheck = [ "vpp_papi" ];

    meta = with lib; {
      description = "VPP Python API bindings";
      homepage = "https://fd.io/";
      license = licenses.asl20;
      maintainers = with maintainers; [ cariandrum22 ];
    };
  };

  # Core VPP package (C/C++ components only)
  vpp-core = stdenv.mkDerivation {
    pname = "vpp";
    inherit version;

    src = vppSrc;

    patches = [ ./0001-explicity-include-std-array.patch ];

    sourceRoot = "vpp/src";

    quicly = callPackage ./quicly { };

    nativeBuildInputs = [
      llvmPackages_18.clang
      cmake
      dpdk'
      intel-ipsec-mb'
      xdp-tools'
      libbpf
      libmnl
      elfutils
      zlib
      (callPackage ./quicly { })
      rdma-core'
      python313
      python313Packages.ply
      openssl
      libuuid
      subunit
      pkg-config
      libpcap
      jansson
      libnl
      libdaq
      srtp'
      check
      libunwind
    ];

    hardeningDisable = [
      "fortify"
      "bindnow"
    ];

    enableParallelBuilding = false;

    env = {
      VPP_BUILD_HOST = "nixpkgs";
    };

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=release"
      "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
      "-DVPP_USE_SYSTEM_DPDK=ON"
      "-DVPP_DISABLED_PLUGINS=tlsmbedtls"
      # Fix RPATH to use install path instead of build path
      "-DCMAKE_INSTALL_RPATH=${placeholder "out"}/lib"
      "-DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF"
      "-DCMAKE_SKIP_BUILD_RPATH=OFF"
      "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=TRUE"
    ];

    postPatch = ''
      # Disable Python API pip install in CMake (we build it separately with Nix)
      # Replace the entire CMakeLists.txt with a minimal version that skips pip install
      cat > vpp-api/python/CMakeLists.txt << 'EOF'
# Minimal CMakeLists.txt for Nix build
# Python API is packaged separately using buildPythonPackage
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(PYTHONINTERP_FOUND ''${Python3_Interpreter_FOUND})
set(PYTHON_EXECUTABLE ''${Python3_EXECUTABLE})
# install() command removed - Python API built separately by Nix
EOF
    '';

    configurePhase = ''
      # Replace script to get version from git describe
      echo "echo ${version}-release" > scripts/version

      # Replace hard-coded bash with one that can be referenced from
      # the built environment
      patchShebangs scripts/generate_version_h

      # Remove pkg from subdirectory to be built.
      # Upstream occasionally reshuffles the surrounding SUBDIRS list, so
      # replacing only the pkg entry is more stable than rewriting the whole line.
      substituteInPlace CMakeLists.txt --replace-fail \
        "    pkg" \
        ""

      # Replace hard-coded python with one that can be referenced from
      # the built environment
      patchShebangs --build tools
      patchShebangs --build vpp-api

      cmake $cmakeFlags .
    '';

    installPhase = ''
      runHook preInstall

      # Use make install with DESTDIR
      make install DESTDIR=$TMPDIR/install

      # Copy installed files to $out
      mkdir -p $out
      if [ -d "$TMPDIR/install/${placeholder "out"}" ]; then
        cp -r "$TMPDIR/install/${placeholder "out"}"/* $out/
      elif [ -d "$TMPDIR/install/usr/local" ]; then
        cp -r $TMPDIR/install/usr/local/* $out/
      else
        cp -r $TMPDIR/install/* $out/
      fi

      runHook postInstall
    '';

    # Fix lib64 -> lib and broken symlinks
    preFixup = ''
      # Move lib64 contents to lib (before Nix's automatic move which can break symlinks)
      if [ -d "$out/lib64" ]; then
        mkdir -p "$out/lib"
        cp -a "$out/lib64"/* "$out/lib/" 2>/dev/null || true
        rm -rf "$out/lib64"
      fi

      # Fix any dangling symlinks by finding the actual versioned files
      for link in "$out/lib"/*.so; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
          target=$(readlink "$link")
          basename_target=$(basename "$target")
          if [ -e "$out/lib/$basename_target" ]; then
            rm "$link"
            ln -s "$basename_target" "$link"
          else
            base_name=$(echo "$basename_target" | sed 's/\.so\..*//')
            versioned_file=$(find "$out/lib" -maxdepth 1 -name "''${base_name}.so.*" -type f | head -1)
            if [ -n "$versioned_file" ]; then
              rm "$link"
              ln -s "$(basename "$versioned_file")" "$link"
            fi
          fi
        fi
      done

      # Fallback: Fix any remaining /build/ RPATH references not handled by CMake
      # This is a safety net in case CMAKE_INSTALL_RPATH doesn't cover all cases
      find "$out" -type f \( -name "*.so*" -o -executable \) | while read -r file; do
        if file "$file" | grep -q "ELF"; then
          current_rpath=$(patchelf --print-rpath "$file" 2>/dev/null || true)
          if echo "$current_rpath" | grep -q "/build/"; then
            new_rpath=$(echo "$current_rpath" | tr ':' '\n' | grep -v "^/build/" | tr '\n' ':' | sed 's/:$//')
            if [ -n "$new_rpath" ]; then
              new_rpath="$out/lib:$new_rpath"
            else
              new_rpath="$out/lib"
            fi
            new_rpath=$(echo "$new_rpath" | tr ':' '\n' | awk '!seen[$0]++' | tr '\n' ':' | sed 's/:$//')
            patchelf --set-rpath "$new_rpath" "$file" 2>/dev/null || true
          fi
        fi
      done
    '';

    meta = with lib; {
      homepage = "https://fd.io/";
      description = "VPP is a fast, scalable layer 2-4 multi-platform network stack";
      longDescription = ''
        FD.io's Vector Packet Processor (VPP) is a fast, scalable layer 2-4
        multi-platform network stack. It runs in Linux Userspace on multiple
        architectures including x86, ARM, and Power architectures.

        VPP's high performance network stack is quickly becoming the network
        stack of choice for applications around the world.

        VPP is continually being enhanced through the extensive use of plugins.
        The Data Plane Development Kit (DPDK) is a great example of this. It
        provides some important features and drivers for VPP.

        VPP supports integration with OpenStack and Kubernetes. Network
        management features include configuration, counters, sampling and more.
        For developers, VPP includes high-performance event-logging, and
        multiple kinds of packet tracing. Development debug images include
        complete symbol tables, and extensive consistency checking.

        Some VPP Use-cases include vSwitches, vRouters, Gateways, Firewalls and
        Load-Balancers, to name a few.
      '';
      license = with licenses; [ asl20 ];
      maintainers = with maintainers; [ cariandrum22 ];
      mainProgram = "vpp";
      platforms = platforms.unix;
    };

    passthru.tests = { inherit (nixosTests) vpp; };
  };

# Combined package: VPP core + Python API
in
symlinkJoin {
  name = "vpp-extended-${version}";

  paths = [
    vpp-core
    vpp-papi
  ];

  passthru = {
    inherit vpp-core vpp-papi;
    tests = vpp-core.passthru.tests;
  };

  meta = vpp-core.meta;
}
