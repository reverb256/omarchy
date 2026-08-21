# VM test: the Omarchy niri desktop boots and the quickshell shell loads
# the qml-niri ports without QML errors. Run via CI (niri-gate) or:
#   nix build .#checks.x86_64-linux.omarchy-niri-vm
{ pkgs, self }:
pkgs.testers.runNixOSTest {
  name = "omarchy-niri-vm";

  nodes.machine = { lib, ... }: {
    imports = [ self.nixosModules.default ];

    programs.omarchy = {
      enable = true;
      compositor = "niri";
      withQuickshellNiri = true;
    };

    programs.niri.enable = true;

    # SDDM autologin into the niri session, like the real host.
    services.displayManager.sddm.enable = true;
    services.displayManager.defaultSession = "niri";
    services.displayManager.autoLogin = {
      enable = true;
      user = "alice";
    };

    users.users.alice = {
      isNormalUser = true;
      extraGroups = [ "video" ];
      password = "";
    };

    virtualisation.memorySize = 2048;
    system.stateVersion = lib.mkDefault "26.05";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("display-manager.service")

    # niri (the compositor) comes up via the niri-session.
    machine.wait_until_succeeds("pgrep -x niri")

    # The omarchy shell (quickshell -n -p $OMARCHY_PATH/shell, launched by
    # the niri autostart) starts and loads the qml-niri shell variants.
    machine.wait_until_succeeds("pgrep -x quickshell")

    # It must stay up — a QML import error would crash-loop it.
    machine.sleep(8)
    machine.succeed("pgrep -x quickshell")

    # No QML module load failures from the shell.
    machine.succeed(
      "! journalctl -t omarchy-shell --no-pager | grep -iE 'module.*not (found|installed)|QML module not|is not installed'"
    )

    # The omarchy router + data tree work in-session (OMARCHY_PATH env).
    machine.succeed("omarchy-theme-list")

    machine.screenshot("niri-omarchy-desktop")
  '';
}
