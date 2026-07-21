{
  description = "A native KDE viewer for Beads";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      inherit (pkgs) lib;
      qtdeclarative = pkgs.kdePackages.qtdeclarative;
      qtQmlCxxFlags = lib.concatStringsSep " " [
        "-I${qtdeclarative}/include"
        "-I${qtdeclarative}/include/QtQml"
        "-I${qtdeclarative}/include/QtQml/${qtdeclarative.version}"
        "-I${qtdeclarative}/include/QtQml/${qtdeclarative.version}/QtQml"
      ];
    in
    {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "kde-beads";
        version = "0.1.0";
        src = ./.;

        cargoLock.lockFile = ./Cargo.lock;

        # qtpaths reports QtBase's prefix, while Nix stores QtDeclarative
        # separately. QtBridge needs these paths for its generated C++.
        CXXFLAGS = qtQmlCxxFlags;

        nativeBuildInputs = with pkgs; [
          pkg-config
          kdePackages.wrapQtAppsHook
        ];

        buildInputs = with pkgs.kdePackages; [
          qtbase
          qtdeclarative
          kirigami
          qqc2-desktop-style
        ];

        qtWrapperArgs = [
          "--prefix PATH : ${lib.makeBinPath [ pkgs.beads ]}"
          "--set-default QT_QUICK_CONTROLS_STYLE org.kde.desktop"
        ];

        postInstall = ''
          install -Dm644 data/io.github.kde_beads.desktop \
            $out/share/applications/io.github.kde_beads.desktop
        '';

        meta = {
          description = "Native KDE viewer for Beads issue trackers";
          license = lib.licenses.mit;
          mainProgram = "kde-beads";
          platforms = [ "x86_64-linux" ];
        };
      };

      apps.${system}.default = {
        type = "app";
        program = lib.getExe self.packages.${system}.default;
        meta.description = "Browse Beads issues with KDE Beads";
      };

      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ self.packages.${system}.default ];
        packages = with pkgs; [
          beads
          cargo
          clippy
          rustc
          rustfmt
        ];

        QT_QUICK_CONTROLS_STYLE = "org.kde.desktop";
        CXXFLAGS = qtQmlCxxFlags;
      };
    };
}
