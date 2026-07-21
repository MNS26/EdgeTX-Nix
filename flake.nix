{
  description = "EdgeTX - Open source RC radio firmware";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    edgetx = {
      type = "git";
      url = "https://github.com/MNS26/EdgeTX";
      ref = "linux";
      submodules = true;
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, flake-utils, edgetx }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        submodules = rec {
          accessDenied = builtins.fetchGit {
            url = "https://github.com/raphaelcoeffic/AccessDenied";
            rev = "6b04dfe4d90870f09b8aa41b8ccf952ba47a55e1";
          };
          freeRtos = builtins.fetchGit {
            url = "https://github.com/FreeRTOS/FreeRTOS-Kernel";
            rev = "dbf70559b27d39c1fdb68dfb9a32140b6a6777a0";
          };
          stb = builtins.fetchGit {
            url = "https://github.com/nothings/stb";
            rev = "5c205738c191bcb0abc65c4febfa9bd25ff35234";
          };
          lvgl = builtins.fetchGit {
            url = "https://github.com/EdgeTX/lvgl";
            ref = "release/v8.2";
            rev = "5f129c540ec43a4e5aebff9f77b3688b57a78063";
          };
          uf2 = builtins.fetchGit {
            url = "https://github.com/microsoft/uf2";
            rev = "d03b585ed780ed51bb0d1e6e8cf233aacb408305";
          };
        };

        setupSubmodules = ''
          echo "Setting up git submodules..."
          mkdir -p radio/src/thirdparty
          ln -sfn ${submodules.accessDenied} radio/src/thirdparty/AccessDenied
          ln -sfn ${submodules.freeRtos} radio/src/thirdparty/FreeRTOS
          ln -sfn ${submodules.stb} radio/src/thirdparty/stb
          ln -sfn ${submodules.lvgl} radio/src/thirdparty/lvgl
          ln -sfn ${submodules.uf2} radio/src/thirdparty/uf2
        '';

        fetchContentDeps = {
          imgui = pkgs.fetchFromGitHub {
            owner = "ocornut";
            repo = "imgui";
            rev = "v1.92.6";
            sha256 = "1q20bkal24w0vqlyy4g5612qd8sjz3p161cm326dx3parxi0gxwk";
          };
          googletest = pkgs.fetchgit {
            url = "https://github.com/google/googletest";
            rev = "f8d7d77c06936315286eb55f8de22cd23c188571";
            sha256 = "19c7f248rkg302yrbl5x7irfyi6a9whbpf45wn4bn9fk0625qi5p";
          };
          rsdfu-x86_64 = pkgs.fetchzip {
            url = "https://github.com/EdgeTX/rs-dfu/releases/latest/download/rs_dfu-x86_64-unknown-linux-gnu.tar.gz";
            sha256 = "0dkmij3f9dl0d1myb71nld9ly4wcwg048dsnqhyc025shaw5zfrk";
          };
          rsdfu-aarch64 = pkgs.fetchzip {
            url = "https://github.com/EdgeTX/rs-dfu/releases/latest/download/rs_dfu-aarch64-unknown-linux-gnu.tar.gz";
            sha256 = "0g59fnxw1xh9nha8hd1q9i98plwdi6vbhhq134x4fgsr71zpr5vw";
          };
          miniz = pkgs.fetchFromGitHub {
            owner = "richgel999";
            repo = "miniz";
            rev = "89d7a5f6c3ce8893ea042b0a9d2a2d9975589ac9";
            sha256 = "18f8nwjw1mz6666m4c7bpb4dv323rr6cmqbpzsjmp9yvxigw1m74";
          };
          yaml-cpp = pkgs.fetchFromGitHub {
            owner = "jbeder";
            repo = "yaml-cpp";
            rev = "28f93bdec6387d42332220afa9558060c8016795";
            sha256 = "15rvc90jprgnvqmclm8digyr7rmwyw0m6d0c575hx2x23bhyrpz7";
          };
          maxLibQt = pkgs.fetchFromGitHub {
            owner = "edgetx";
            repo = "maxLibQt";
            rev = "7e433da60d3f2e975d46afc91804a88029cd1b78";
            sha256 = "09ghqn3gbk0q2y7ykdsp36y44dgv6k0fn3wpbixlyb2da16pryfl";
          };
          wamr = pkgs.fetchgit {
            url = "https://github.com/bytecodealliance/wasm-micro-runtime";
            rev = "WAMR-2.4.4";
            sha256 = "13njx6qd5ach18fyiwqajqjry17z85bbbdj9ggc1yxg1m429vnx4";
          };
        };

        nativeFcFlagsAarch64 = [
          "-DFETCHCONTENT_SOURCE_DIR_IMGUI=${fetchContentDeps.imgui}"
          "-DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=${fetchContentDeps.googletest}"
          "-DFETCHCONTENT_SOURCE_DIR_RSDFU=${fetchContentDeps.rsdfu-aarch64}"
          "-DFETCHCONTENT_SOURCE_DIR_MINIZ=${fetchContentDeps.miniz}"
          "-DFETCHCONTENT_SOURCE_DIR_YAML-CPP=${fetchContentDeps.yaml-cpp}"
          "-DFETCHCONTENT_SOURCE_DIR_MAXLIBQT=${fetchContentDeps.maxLibQt}"
          "-DFETCHCONTENT_SOURCE_DIR_WAMR=$PWD/.fc-staging/wamr"
        ];
        extraCmakeFlags = [ "-Wno-dev" "-Wno-cpp"];

        wamrStageCmd = ''
          mkdir -p $PWD/.fc-staging
          cp -r --no-preserve=mode ${fetchContentDeps.wamr} $PWD/.fc-staging/wamr
          chmod -R +w $PWD/.fc-staging/wamr
        '';

        nixSystemIncludeDirs = builtins.concatStringsSep ":" [
          "${pkgs.stdenv.cc.cc}/include/c++/${pkgs.stdenv.cc.cc.version}"
          "${pkgs.stdenv.cc.cc}/include/c++/${pkgs.stdenv.cc.cc.version}/${pkgs.stdenv.targetPlatform.config}"
          "${pkgs.stdenv.cc.cc}/lib/gcc/${pkgs.stdenv.targetPlatform.config}/${pkgs.stdenv.cc.cc.version}/include"
          "${pkgs.glibc.dev}/include"
        ];

        postPatch = ''
          ${pkgs.python3}/bin/python3 -c "
          import os, sys

          # patch generate_datacopy.py
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

          # patch generate_yaml.py (different indentation)
          path = 'radio/util/generate_yaml.py'
          old = 'if find_clang.builtin_hdr_path:\n    args.append(\"-I\" + find_clang.builtin_hdr_path)'
          new = 'if find_clang.builtin_hdr_path:\n    args.append(\"-I\" + find_clang.builtin_hdr_path)\n_nix_dirs = os.environ.get(\"NIX_SYSTEM_INCLUDE_DIRS\", \"\")\nif _nix_dirs:\n    for _d in _nix_dirs.split(\":\"):\n        if os.path.isdir(_d):\n            args.append(\"-idirafter\")\n            args.append(_d)'
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

        # ---- Firmware package ----
        mkFirmware = attrs: pkgs.callPackage ./firmware.nix ( { edgetx-src = edgetx; inherit setupSubmodules; NIX_SYSTEM_INCLUDE_DIRS = nixSystemIncludeDirs; } // attrs);
        # ---- Native SDL simulator ----
        mkSimu = attrs: pkgs.callPackage ./simu.nix ({ edgetx-src = edgetx; inherit fetchContentDeps setupSubmodules; NIX_SYSTEM_INCLUDE_DIRS = nixSystemIncludeDirs; postPatch = postPatch; } // attrs);
        # ---- Companion + Standalone Simulator (Qt6) ----
        mkCompanion = attrs: pkgs.callPackage ./companion.nix ({ inherit fetchContentDeps; edgetx-src = edgetx; NIX_SYSTEM_INCLUDE_DIRS = nixSystemIncludeDirs; } // attrs);
        

      in
      {
        packages = {

          edgetx-firmware-tx16s = mkFirmware {
            pcb = "X10";
            pcbrev = "TX16S";
          };

          edgetx-simu-tx16s = mkSimu {
            pcb = "X10";
            pcbrev = "TX16S";
          };

          edgetx-linux = mkSimu {
            pcb = "LINUX";
            pcbrev = "";
            cmakeBuildTarget = "linux";
            extraCmakeFlags = extraCmakeFlags ++ [ "-DSIMU_TARGET=OFF" ];
          };

          edgetx-simu-linux = mkSimu {
            pcb = "LINUX";
            pcbrev = "";
            cmakeBuildTarget = "simu";
            extraCmakeFlags = extraCmakeFlags;
          };

          edgetx-companion = mkCompanion { };

        }
        # Cross-compiled simu for Raspberry Pi 5 (aarch64) — only from x86_64
        // (if system == "x86_64-linux" then
          let
            pkgsArm = import nixpkgs {
              inherit system;
              crossSystem = nixpkgs.lib.systems.examples.aarch64-multiplatform;
              overlays = [
                # sdl2-compat's cmake defaults to SDL2COMPAT_X11=ON even when
                # x11Support=false; it only removes libx11 from buildInputs
                # but doesn't pass -DSDL2COMPAT_X11=OFF to cmake, causing
                # cross-compile to fail finding X11 headers.
                # needs to be build from src without X11
                (final: prev: {
                  enableSystemd = false;
                  sdl2-compat = (prev.sdl2-compat.override { x11Support = false; }).overrideAttrs (old: {
                    cmakeFlags = (old.cmakeFlags or []) ++ [
                      "-DSDL2COMPAT_X11=OFF"
                    ];
                  });
                })
              ];
            };

            aarch64Toolchain = builtins.toFile "toolchain-aarch64.cmake" ''
              set(CMAKE_SYSTEM_NAME Linux)
              set(CMAKE_SYSTEM_PROCESSOR aarch64)
              set(CMAKE_CXX_STANDARD 17)
              set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
              set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
              set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
            '';

            pythonDepsArm = with pkgsArm.pkgsBuildBuild.python3Packages; [
              asciitree
              jinja2
              pillow
              libclang
              lz4
              pyelftools
              pydantic
            ];

          in
          {
            edgetx-linux-aarch64 = pkgsArm.stdenv.mkDerivation {
              pname = "edgetx-linux-aarch64";
              version = "3.0.0";
              src = edgetx;

              nativeBuildInputs = [
                pkgs.cmake
                pkgs.git
                pkgs.python3
                pkgs.cacert
              ] ++ pythonDepsArm;

              buildInputs = [
                pkgsArm.SDL2
                pkgsArm.openssl
              ];

              SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

              # generate_datacopy.py runs on build host (x86_64), so use build-host headers
              NIX_SYSTEM_INCLUDE_DIRS = nixSystemIncludeDirs;

              postPatch = postPatch;
            
              preConfigure = setupSubmodules + wamrStageCmd;

              configurePhase = ''
                runHook preConpsfigure
                cmake -B build -S . \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DCMAKE_TOOLCHAIN_FILE=${aarch64Toolchain} \
                  -DEdgeTX_SUPERBUILD=OFF \
                  -DNATIVE_BUILD=ON \
                  -DPCB=X10 -DPCBREV=TX16S \
                  -DCMAKE_TLS_VERIFY=OFF \
                  -DDISABLE_COMPANION=ON \
                  ${builtins.concatStringsSep " \\\n                  " nativeFcFlagsAarch64} \
                  -Wno-dev
                runHook postConfigure
              '';

              postConfigure = ''
                rm -rf build/simu    # remove directory, clear path for binary
              '';

              buildPhase = ''
                runHook preBuild
                cmake --build build --target simu -j$(($NIX_BUILD_CORES-1))
                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall
                mkdir -p $out/bin
                cp build/simu $out/bin/
                runHook postInstall
              '';

              enableParallelBuilding = true;

              meta.mainProgram = "simu";
            };
          }
        else { });

        apps = {
          # Runnable apps
          simu = flake-utils.lib.mkApp {
            drv = self.packages.${system}.edgetx-simu;
            name = "simu";
          };
          companion = flake-utils.lib.mkApp {
            drv = self.packages.${system}.edgetx-companion;
            name = "companion";
          };

          # Build apps — each creates a named --out-link so builds don't overwrite each other
          build-firmware = {
            type = "app";
            program = let
              script = pkgs.writeShellScript "build-firmware" ''
                exec nix build "path:${toString ./.}#edgetx-firmware-tx16s" \
                  --out-link firmware \
                  --impure "$@"
              '';
            in "${script}";
          };
          build-simu = {
            type = "app";
            program = let
              script = pkgs.writeShellScript "build-simu" ''
                exec nix build "path:${toString ./.}#edgetx-simu" \
                  --out-link simu \
                  --impure "$@"
              '';
            in "${script}";
          };
          build-companion = {
            type = "app";
            program = let
              script = pkgs.writeShellScript "build-companion" ''
                exec nix build "path:${toString ./.}#edgetx-companion" \
                  --out-link edgetx-companion \
                  --impure "$@"
              '';
            in "${script}";
          };
          build-simu-aarch64 = {
            type = "app";
            program = let
              script = pkgs.writeShellScript "build-simu-aarch64" ''
                exec nix build "path:${toString ./.}#edgetx-simu-aarch64" \
                  --out-link simu-aarch64 \
                  --impure "$@"
              '';
            in "${script}";
          };
          build-simu-linux = {
            type = "app";
            program = let
              script = pkgs.writeShellScript "build-simu-linux" ''
                exec nix build "path:${toString ./.}#edgetx-simu-linux" \
                  --out-link edgetx-simu-linux \
                  --impure "$@"
              '';
            in "${script}";
          };

          build-linux = {
            type = "app";
            program = let
              script = pkgs.writeShellScript "build-linux" ''
                exec nix build "path:${toString ./.}#edgetx-linux" \
                  --out-link edgetx-linux \
                  --impure "$@"
              '';
            in "${script}";
          };
        };

        devShells.default = pkgs.mkShell {
          name = "edgetx-dev";

          inputsFrom = [
            (mkSimu { extraNativeBuildInputs = [ pkgs.gcc-arm-embedded ]; })
            (mkCompanion { })
          ];

          packages = [ pkgs.gcc-arm-embedded pkgs.nodejs pkgs.lv_font_conv ];

          NIX_SYSTEM_INCLUDE_DIRS = nixSystemIncludeDirs;
          C_INCLUDE_PATH = nixSystemIncludeDirs;
          CPLUS_INCLUDE_PATH = nixSystemIncludeDirs;

          # A simple banner with all options for the shell
          # shitty but works
          shellHook = ''
            echo "EdgeTX development shell"
            echo "Build commands (aliases):"
            echo "  nix run .#build-firmware      -> builds firmware, creates firmware/ symlink"
            echo "  nix run .#build-simu          -> builds SDL simu, creates simu/ symlink"
            echo "  nix run .#build-companion     -> builds companion, creates edgetx-companion/ symlink"
            echo "  nix run .#build-linux-aarch64 -> cross-compiles simu for ARM, creates simu-aarch64/ symlink"
            echo "  nix run .#build-simu-linux    -> builds SDL simu (Linux target), creates simu-linux/ symlink"
            echo "  nix run .#build-linux         -> builds Linux standalone, creates edgetx-linux/ symlink"
            echo ""
          '';
        };
      });
}
