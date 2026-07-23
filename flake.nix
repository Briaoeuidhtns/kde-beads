{
  description = "A native KDE viewer for Beads";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      inherit (pkgs) lib;
      qtdeclarative = pkgs.kdePackages.qtdeclarative;
      qtNativeBuildInputs = with pkgs; [
        pkg-config
        kdePackages.wrapQtAppsHook
      ];
      qtBuildInputs = with pkgs.kdePackages; [
        qtbase
        qtdeclarative
        kdeclarative
        kirigami
        qqc2-desktop-style
      ];
      qtRuntimeInputs = qtBuildInputs ++ (with pkgs.kdePackages; [
        kirigami.unwrapped
        sonnet
      ]);
      qtQmlImportPath = lib.makeSearchPath "lib/qt-6/qml" qtRuntimeInputs;
      qtPluginPath = lib.makeSearchPath "lib/qt-6/plugins" qtRuntimeInputs;
      qtQmlCxxFlags = lib.concatStringsSep " " [
        "-I${qtdeclarative}/include"
        "-I${qtdeclarative}/include/QtQml"
        "-I${qtdeclarative}/include/QtQml/${qtdeclarative.version}"
        "-I${qtdeclarative}/include/QtQml/${qtdeclarative.version}/QtQml"
      ];
    in
    {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "knecklace";
        version = "0.1.0";
        src = ./.;

        cargoLock.lockFile = ./Cargo.lock;

        # qtpaths reports QtBase's prefix, while Nix stores QtDeclarative
        # separately. QtBridge needs these paths for its generated C++.
        CXXFLAGS = qtQmlCxxFlags;

        nativeBuildInputs = qtNativeBuildInputs;
        nativeCheckInputs = with pkgs; [ beads git ];
        buildInputs = qtBuildInputs;

        preCheck = ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
        '';

        qtWrapperArgs = [
          "--prefix PATH : ${lib.makeBinPath [ pkgs.beads pkgs.kdePackages.kdialog ]}"
          "--set-default QT_QUICK_CONTROLS_STYLE org.kde.desktop"
        ];

        postInstall = ''
          install -Dm644 data/io.github.knecklace.desktop \
            $out/share/applications/io.github.knecklace.desktop
        '';

        meta = {
          description = "Native KDE viewer for Beads repositories";
          license = lib.licenses.mit;
          mainProgram = "knecklace";
          platforms = [ "x86_64-linux" ];
        };
      };

      apps.${system}.default = {
        type = "app";
        program = lib.getExe self.packages.${system}.default;
        meta.description = "Browse beads with Knecklace";
      };

      checks.${system}.tests = pkgs.rustPlatform.buildRustPackage {
        pname = "knecklace-tests";
        version = "0.1.0";
        src = self;

        cargoLock.lockFile = ./Cargo.lock;
        CXXFLAGS = qtQmlCxxFlags;
        QT_QUICK_CONTROLS_STYLE = "org.kde.desktop";
        QML2_IMPORT_PATH = qtQmlImportPath;
        QML_IMPORT_PATH = qtQmlImportPath;
        QT_PLUGIN_PATH = qtPluginPath;

        nativeBuildInputs = qtNativeBuildInputs ++ (with pkgs; [
          beads
          cargo-nextest
          git
          kdePackages.qtdeclarative
        ]);
        buildInputs = qtBuildInputs;

        doCheck = true;
        checkPhase = ''
          runHook preCheck
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          bash ./scripts/test
          runHook postCheck
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p "$out"
          cp target/test-results/*.xml "$out/"
          runHook postInstall
        '';
      };

      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ self.packages.${system}.default ];
        packages = with pkgs; [
          beads
          cargo
          cargo-nextest
          clippy
          git
          kdePackages.kdialog
          rustc
          rustfmt
        ];

        QT_QUICK_CONTROLS_STYLE = "org.kde.desktop";
        CXXFLAGS = qtQmlCxxFlags;
      };
    };
}
