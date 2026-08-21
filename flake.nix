{
  description = "Reverb-OS Omarchy — downstream fork: Omarchy (quattro) + additive Niri layer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # qml-niri — third-party `import Niri` QML plugin for the niri compositor.
    # Its nixpkgs follows ours so the Qt6 ABI matches the quickshell we build.
    qml-niri = {
      url = "git+https://github.com/imiric/qml-niri?rev=93e603901bed2c4465d5675ae43fd52b7f7c4adf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , qml-niri
    , ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        # The Omarchy UX layer as a data-file runtime: $out/share/omarchy
        # (the OMARCHY_PATH root) + bin/omarchy* symlink farm. Upstream files
        # stay pristine; the Niri adaptation is the additive shell-niri/ and
        # bin-niri/ trees, selected by `compositor`.
        omarchy = pkgs.callPackage ./nix/package.nix {
          src = self;
        };
        # The Niri variant — shell-niri/ QML overlays + bin-niri/ commands
        # baked in. Explicit output so consumers and CI can target it directly.
        omarchy-niri = pkgs.callPackage ./nix/package.nix {
          src = self;
          compositor = "niri";
        };
        # quickshell with the qml-niri plugin wired into QML_IMPORT_PATH
        # (wrapQtAppsHook picks it up from buildInputs automatically).
        quickshell-niri = pkgs.quickshell.overrideAttrs (old: {
          buildInputs = (old.buildInputs or [ ]) ++ [ qml-niri.packages.${system}.default ];
        });
        default = self.packages.${system}.omarchy;
      };

      overlays.default = final: prev: {
        omarchy = prev.callPackage ./nix/package.nix { };
        quickshell-niri = prev.quickshell.overrideAttrs (old: {
          buildInputs = (old.buildInputs or [ ]) ++ [ qml-niri.packages.${system}.default ];
        });
      };

      nixosModules.default = import ./nix/nixos-module.nix self;

      checks.${system} = {
        # Every shell-niri/ variant must shadow a real upstream shell/ file;
        # a mismatch means upstream moved the QML and we drifted.
        shell-niri-shadows-upstream = pkgs.runCommand "shell-niri-drift-check" { } ''
          cd ${self}
          fail=0
          for f in $(find shell-niri -type f); do
            upstream="shell/''${f#shell-niri/}"
            if [ ! -f "$upstream" ]; then
              echo "DRIFT: $f has no shell/ counterpart (upstream moved it)"
              fail=1
            fi
          done
          if [ "$fail" = 1 ]; then
            echo "shell-niri/ is out of sync with upstream shell/ — re-derive the variants."
            exit 1
          fi
          echo "All shell-niri/ variants shadow an upstream shell/ file ✓"
          touch $out
        '';
      };
    };
}
