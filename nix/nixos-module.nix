# Thin enable module for the Reverb-OS omarchy fork. All adaptation lives in
# the fork's package (compositor-selected shell-niri/bin-niri overlays); the
# cluster keeps only this module.
self:
{ lib, config, pkgs, ... }:
let
  cfg = config.programs.omarchy;
  omarchy = self.packages.${pkgs.system}.omarchy.override { compositor = cfg.compositor; };
in
{
  options.programs.omarchy = {
    enable = lib.mkEnableOption "Omarchy UX layer (Reverb-OS downstream fork)";

    compositor = lib.mkOption {
      type = lib.types.enum [ "hyprland" "niri" ];
      default = "hyprland";
      description = ''
        Compositor the additive layer targets. "hyprland" is pure upstream;
        "niri" selects the shell-niri/ QML variants and bin-niri/ commands at
        build time and sets OMARCHY_COMPOSITOR=niri for the session.
      '';
    };

    withQuickshellNiri = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install quickshell-niri (quickshell + qml-niri plugin) for the niri shell.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ omarchy ]
      ++ lib.optionals cfg.withQuickshellNiri [ self.packages.${pkgs.system}.quickshell-niri ];

    environment.sessionVariables = {
      OMARCHY_PATH = "${omarchy}/share/omarchy";
      OMARCHY_COMPOSITOR = cfg.compositor;
    };
  };
}
