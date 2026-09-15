{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  openssl,
  perl,
  pkg-config,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "quicly";
  version = "0.1.6-vpp";

  src = fetchFromGitHub {
    owner = "vpp-quic";
    repo = "quicly";
    tag = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-MJ3LNdU+CtLB000BkSNTiOvIzbSje4i9VKEBG+NpYlk=";
  };

  patches = [
    ./0001-cmake-install.patch
    ./0002-cmake-install-picotls.patch
    ./0003-unused-is-late-ack.patch
  ];

  nativeBuildInputs = [
    cmake
    perl
    pkg-config
  ];

  buildInputs = [ openssl ];

  configurePhase = ''
    runHook preConfigure
    mkdir -p build-quicly build-picotls
    cmake -DWITH_DTRACE=OFF -DCMAKE_INSTALL_PREFIX:PATH=$out -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -S . -B build-quicly
    cmake -DWITH_DTRACE=OFF -DCMAKE_INSTALL_PREFIX:PATH=$out -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -S deps/picotls -B build-picotls
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j $NIX_BUILD_CORES -C build-quicly
    make picotls-core picotls-openssl -j $NIX_BUILD_CORES -C build-picotls
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make -C build-quicly install
    make picotls-core picotls-openssl -C build-picotls install
    runHook postInstall
  '';

  meta = {
    description = "VPP-compatible Quicly and Picotls libraries";
    homepage = "https://github.com/vpp-quic/quicly";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.cariandrum22 ];
    platforms = lib.platforms.unix;
  };
})
