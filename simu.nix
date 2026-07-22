{ stdenv
, edgetx-src
, glibc
, SDL2
, openssl
, libx11
, cacert
, cmake
, git
, python3
, lib
, fetchContentDeps
, fetchzip
, setupSubmodules ? ""
, NIX_SYSTEM_INCLUDE_DIRS ? ""
, sd-path ? null
, sdcard ? null
, postPatch ? ""
, pcb ? "X10",
  pcbrev ? "TX16S",
  buildType ? "Release",
  autosource ? "ON",
  autoswitch ? "ON",
  bootloader ? "OFF",
  curves ? "ON",
  flightmodes ? "ON",
  gvars ? "ON",
  lua ? "ON",
  luacompiler ? "ON",
  luamixer ? "ON",
  extraNativeBuildInputs ? [ ],
  extraBuildInputs ? [ ] ,
  extraCmakeFlags ? [ ],
  cmakeBuildTarget ? "simu",
}:
let
  wamrStageCmd = ''
    mkdir -p $PWD/.fc-staging
    cp -r --no-preserve=mode ${fetchContentDeps.wamr} $PWD/.fc-staging/wamr
    chmod -R +w $PWD/.fc-staging/wamr
  '';
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
/*
  pkgs = import nixpkgs {
    inherit system;
    overlays = [
      # sdl2-compat cmake defaults to SDL2COMPAT_X11=ON even when
      # x11Support=false; it only removes libx11 from buildInputs
      # but doesn't pass -DSDL2COMPAT_X11=OFF to cmake, causing
      # cross-compile to fail finding X11 headers.
      # needs to be build from src without X11
      (final: prev: {
        SDL2_wayland = (prev.sdl2-compat.override { x11Support = false; })
        .overrideAttrs (old: {
          cmakeFlags = (old.cmakeFlags or []) ++ [
            "-DSDL2COMPAT_X11=OFF"
          ];
        });
      })
    ];
  };
*/
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=${buildType}"
    "-DCMAKE_TOOLCHAIN_FILE=cmake/toolchain/native.cmake"
    "-DEdgeTX_SUPERBUILD=OFF"
    "-DNATIVE_BUILD=ON"
    "-DCMAKE_TLS_VERIFY=OFF"
    "-DDISABLE_COMPANION=ON"
    "-DAUDIO=ON"
    "-DAUTOSOURCE=${autosource}"
    "-DAUTOSWITCH=${autoswitch}"
    "-DBOOTLOADER=${bootloader}"
    "-DCURVES=${curves}"
    "-DFLIGHT_MODES=${flightmodes}"
    "-DGVARS=${gvars}"
    "-DLUA=${lua}"
    "-DLUA_COMPILER=${luacompiler}"
    "-DLUA_MIXER=${luamixer}"
    "-DPCB=${pcb}"
  ] ++ lib.optionals (pcbrev != "") [
    "-DPCBREV=${pcbrev}"
  ] ++ extraCmakeFlags ++ nativeFcFlags;
  myPython = python3.withPackages (ps: with ps; [
    pillow
    lz4
    jinja2
    pydantic
    libclang
    asciitree
  ]);
  
  output-name = if cmakeBuildTarget == "simu" then "simu" else "edgetx";
in
stdenv.mkDerivation {
  pname = "edgetx-${cmakeBuildTarget}";
  version = "3.0.0";
  src = edgetx-src;

  nativeBuildInputs = [
      cacert
      cmake
      git
      myPython
    ] ++ extraNativeBuildInputs;

  buildInputs = [
    SDL2
    openssl
    libx11
  ] ++ extraBuildInputs;

  inherit NIX_SYSTEM_INCLUDE_DIRS;

  inherit postPatch;

  # postPatch = ''
  #   python3 -c "
  #   import os, sys

  #   # patch generate_datacopy.py
  #   path = 'radio/util/generate_datacopy.py'
  #   old = '    if find_clang.builtin_hdr_path:\n        args.append(\"-I\" + find_clang.builtin_hdr_path)'
  #   new = '    if find_clang.builtin_hdr_path:\n        args.append(\"-I\" + find_clang.builtin_hdr_path)\n    _nix_dirs = os.environ.get(\"NIX_SYSTEM_INCLUDE_DIRS\", \"\")\n    if _nix_dirs:\n        for _d in _nix_dirs.split(\":\"):\n            if os.path.isdir(_d):\n                args.append(\"-idirafter\")\n                args.append(_d)'
  #   with open(path) as f:
  #       c = f.read()
  #   if old not in c:
  #       print('ERROR: pattern not found in ' + path)
  #       print(repr(old))
  #       sys.exit(1)
  #   c = c.replace(old, new)
  #   with open(path, 'w') as f:
  #       f.write(c)

  #   # patch generate_yaml.py (different indentation)
  #   path = 'radio/util/generate_yaml.py'
  #   old = 'if find_clang.builtin_hdr_path:\n    args.append(\"-I\" + find_clang.builtin_hdr_path)'
  #   new = 'if find_clang.builtin_hdr_path:\n    args.append(\"-I\" + find_clang.builtin_hdr_path)\n_nix_dirs = os.environ.get(\"NIX_SYSTEM_INCLUDE_DIRS\", \"\")\nif _nix_dirs:\n    for _d in _nix_dirs.split(\":\"):\n        if os.path.isdir(_d):\n            args.append(\"-idirafter\")\n            args.append(_d)'
  #   with open(path) as f:
  #       c = f.read()
  #   if old not in c:
  #       print('ERROR: pattern not found in ' + path)
  #       print(repr(old))
  #       sys.exit(1)
  #   c = c.replace(old, new)
  #   with open(path, 'w') as f:
  #       f.write(c)
  #   "
  # '';

  preConfigure = setupSubmodules + wamrStageCmd;

  configurePhase = ''
    runHook preConfigure
    unset SOURCE_DATE_EPOCH
    cmake -B build -S . ${builtins.concatStringsSep " " cmakeFlags}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build --target ${cmakeBuildTarget} -j$(($NIX_BUILD_CORES-1))
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp build/${cmakeBuildTarget} $out/bin/.${output-name}
    rm -rf build
    runHook postInstall

    cat <<EOF > $out/bin/${output-name}
    #!/bin/bash
    ${lib.optionalString (sdcard != null) ''

    if [[ ! -e "${sd-path}" ]]; then
      mkdir -p ${sd-path}
    fi
    for folder in ${sdcard}/*; do
      cp -r "\''${folder}" ${sd-path}/
    done

    cd ${sd-path}
    ''}
    $out/bin/.${output-name} "\''$@"
    EOF
    chmod +x $out/bin/${output-name}
  '';

  enableParallelBuilding = true;

  meta.mainProgram = "${cmakeBuildTarget}";
}
