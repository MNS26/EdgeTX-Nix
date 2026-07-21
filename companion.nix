{ stdenv
, SDL2
, lib
, edgetx-src
, glibc
, openssl
, cmake
, git
, python3
, qt6
, fetchContentDeps
, extraNativeBuildInputs ? [ ]
, extraBuildInputs ? [ ]
, NIX_SYSTEM_INCLUDE_DIRS ? ""

}:
let
  # All NATVIE_BUILD=ON targets (simu, companion) configure companion/
  # at cmake time, All FetchContent deps must be overridden for every build.
  # WAMR is staged as a writable copy because it needs write access during
  # configure (version.h generation). ($PWD expands at build time in bash)
  nativeFcFlags = [
    "-DFETCHCONTENT_SOURCE_DIR_IMGUI=${fetchContentDeps.imgui}"
    "-DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=${fetchContentDeps.googletest}"
    "-DFETCHCONTENT_SOURCE_DIR_RSDFU=${fetchContentDeps.rsdfu-x86_64}"
    "-DFETCHCONTENT_SOURCE_DIR_MINIZ=${fetchContentDeps.miniz}"
    "-DFETCHCONTENT_SOURCE_DIR_YAML-CPP=${fetchContentDeps.yaml-cpp}"
    "-DFETCHCONTENT_SOURCE_DIR_MAXLIBQT=${fetchContentDeps.maxLibQt}"
    "-DFETCHCONTENT_SOURCE_DIR_WAMR=$PWD/.fc-staging/wamr"
  ];
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_TOOLCHAIN_FILE=cmake/toolchain/native.cmake"
    "-DEdgeTX_SUPERBUILD=OFF"
    "-DNATIVE_BUILD=ON"
    "-DCMAKE_TLS_VERIFY=OFF"
  ] ++ nativeFcFlags;
  wamrStageCmd = ''
    mkdir -p $PWD/.fc-staging
    cp -r --no-preserve=mode ${fetchContentDeps.wamr} $PWD/.fc-staging/wamr
    chmod -R +w $PWD/.fc-staging/wamr
  '';
in
stdenv.mkDerivation {
  pname = "edgetx-companion";
  version = "3.0.0";
  src = edgetx-src;

  nativeBuildInputs = [
    cmake
    git
    python3
    qt6.wrapQtAppsHook
  ] ++ extraNativeBuildInputs;
  buildInputs = [
    SDL2
    openssl
    qt6.qtbase
    qt6.qtmultimedia
    qt6.qtserialport
    qt6.qtsvg
    qt6.qttools
  ] ++ extraBuildInputs;

  # NIX_SYSTEM_INCLUDE_DIRS = lib.concatStringsSep ":" [
  #   "${glibc.dev}/include"
  #   "${stdenv.cc.cc}/include/c++/${stdenv.cc.cc.version}"
  #   "${stdenv.cc.cc}/include/c++/${stdenv.cc.cc.version}/${stdenv.targetPlatform.config}"
  #   "${stdenv.cc.cc}/lib/gcc/${stdenv.targetPlatform.config}/${stdenv.cc.cc.version}/include"
  # ];

  inherit NIX_SYSTEM_INCLUDE_DIRS;

  postPatch = ''
    python3 -c "
    import os, sys
    path = 'radio/util/generate_datacopy.py'
    old = '    if find_clang.builtin_hdr_path:\n        args.append(\"-I\" + find_clang.builtin_hdr_path)'
    new = '    if find_clang.builtin_hdr_path:\n        args.append(\"-I\" + find_clang.builtin_hdr_path)\n    _nix_dirs = os.environ.get(\"NIX_SYSTEM_INCLUDE_DIRS\", \"\")\n    if _nix_dirs:\n        for _d in _nix_dirs.split(\":\"):\n            if os.path.isdir(_d):\n                args.append(\"-idirafter\")\n                args.append(_d)'
    with open(path) as f:
        c = f.read()
    if old not in c:
        print('ERROR: pattern not found in ' + path)
        print(repr(old))
        sys.exit(1)
    c = c.replace(old, new)
    with open(path, 'w') as f:
        f.write(c)
    "
  '';

  preConfigure = wamrStageCmd;

  configurePhase = ''
    runHook preConfigure
    cmake -B build -S . ${builtins.concatStringsSep " " cmakeFlags} -Wno-dev
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build --target companion -j$(($NIX_BUILD_CORES-1))
    cmake --build build --target simulator -j$(($NIX_BUILD_CORES-1))
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp build/companion30 $out/bin/companion
    if [ -f build/simulator30 ]; then
      cp build/simulator30 $out/bin/simulator
    elif [ -f build/simu ]; then
      cp build/simu $out/bin/simulator
    fi
    runHook postInstall
  '';

  enableParallelBuilding = true;

  meta.mainProgram = "companion";
}
