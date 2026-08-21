# Thin enable module for the Reverb-OS omarchy fork. All adaptation lives in
# the fork's package (compositor-selected shell-niri/bin-niri overlays) and
# config-niri/ (niri config fragments); the consumer keeps only this module.
self:
{ lib, config, pkgs, ... }:
let
  cfg = config.programs.omarchy;
  system = pkgs.stdenv.hostPlatform.system;
  omarchy = self.packages.${system}.omarchy.override { compositor = cfg.compositor; };

  # Niri config is assembled from the config-niri/ fragments (source of
  # truth), in load order. niri reads config.kdl from $XDG_CONFIG_DIRS/niri
  # (default /etc/xdg) when no user config exists.
  niriFragmentOrder = [
    "envs"
    "input"
    "monitors"
    "looknfeel"
    "autostart"
    "bindings"
    "windows"
    "workspaces"
  ];
  niriConfigText = builtins.concatStringsSep "\n" (
    map (f: builtins.readFile "${self}/config-niri/${f}.kdl") niriFragmentOrder
  );
  # The polkit agent lives in libexec, not on PATH — interpolate its store path.
  niriConfigText' = builtins.replaceStrings
    [ "@polkit@/libexec/polkit-gnome-authentication-agent-1" ]
    [ "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1" ]
    niriConfigText;

  # Hyprland-service parity: idle/lock/nightlight/wallpaper/picker/OSD/portal.
  niriServicePackages = with pkgs; [
    swaybg
    swayidle
    swaylock
    swayosd
    grim
    slurp
    wlsunset
    xwayland-satellite
    xdg-desktop-portal-gtk
    polkit_gnome
    wl-clip-persist
  ];
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
        build time, installs the parity service packages, writes the niri
        config, and sets OMARCHY_COMPOSITOR=niri for the session.
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
      ++ lib.optionals (cfg.compositor == "niri") (
        [ self.packages.${system}.quickshell-niri ] ++ niriServicePackages
      );

    environment.etc."xdg/niri/config.kdl" = lib.mkIf (cfg.compositor == "niri") {
      text = niriConfigText';
    };

    environment.sessionVariables = {
      OMARCHY_PATH = "${omarchy}/share/omarchy";
      OMARCHY_COMPOSITOR = cfg.compositor;
    };
  };
}
