{ stdenv
, cmake
, git
, edgetx-src
, python3
, glibc
, gcc-arm-embedded
, clang
, lib
, setupSubmodules ? ""
, NIX_SYSTEM_INCLUDE_DIRS ? ""
, pcb ? "",
  pcbrev ? "",
  autosource ? "ON",
  autoswitch ? "ON",
  curves ? "ON",
  flightmodes ? "ON",
  gvars ? "ON",
  lua ? "ON",
  luacompiler ? "ON",
  luamixer ? "ON"
}:
let
  lower = lib.strings.toLower;
  clean = s: builtins.replaceStrings [ "+" ] [ "p" ] s;
  pname = "edgetx-firmware-${clean (lower pcb)}-${clean (lower (if pcbrev != "" then pcbrev else pcb))}";
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_TOOLCHAIN_FILE=cmake/toolchain/arm-none-eabi.cmake"
    "-DEdgeTX_SUPERBUILD=OFF"
    "-DNATIVE_BUILD=OFF"
    "-DUSE_UNSUPPORTED_TOOLCHAIN=ON"
    "-DAUTOSOURCE=${autosource}"
    "-DAUTOSWITCH=${autoswitch}"
    "-DCURVES=${curves}"
    "-DFLIGHT_MODES=${flightmodes}"
    "-DGVARS=${gvars}"
    "-DLUA=${lua}"
    "-DLUA_COMPILER=${luacompiler}"
    "-DLUA_MIXER=${luamixer}"
    "-DPCB=${pcb}"
  ] ++ lib.optionals (pcbrev != "") [
    "-DPCBREV=${pcbrev}"
  ];
  myPython = python3.withPackages (ps: with ps; [
    pillow
    lz4
    jinja2
    pydantic
    libclang
    asciitree
  ]);
in
stdenv.mkDerivation {
  inherit pname;
  version = "3.0.0";
  src = edgetx-src;

  nativeBuildInputs = [
    cmake
    git
    myPython
    gcc-arm-embedded
    clang
  ];

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

  preConfigure = setupSubmodules;

  configurePhase = ''
    runHook preConfigure
    cmake -B build -S . ${builtins.concatStringsSep " " cmakeFlags} -Wno-dev
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build --target firmware -j$(($NIX_BUILD_CORES-1))
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp build/firmware.bin $out/
    cp build/firmware.elf $out/
    runHook postInstall
  '';

  enableParallelBuilding = true;
}
