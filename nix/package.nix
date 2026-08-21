{
  lib,
  stdenvNoCC,
  src,
  compositor ? "hyprland",
}:
# omarchy — Reverb-OS downstream fork of basecamp/omarchy (quattro).
#
# Upstream installs to /usr/share/omarchy (the OMARCHY_PATH runtime root) and
# exposes bin/omarchy* on PATH. We reproduce that layout in the Nix store:
#   $out/share/omarchy/          — the verbatim upstream tree (bin, themes,
#                                  shell, config, default, applications,
#                                  manual, install, migrations, version)
#   $out/bin/omarchy*            — symlink farm for the router + commands
#
# The fork's additive Niri layer (shell-niri/ + bin-niri/, upstream files
# untouched) is selected at build time by `compositor`:
#   compositor = "hyprland"  — pure upstream (default)
#   compositor = "niri"      — shell-niri/ QML overlays shell/ (the qml-niri
#                              ports) and bin-niri/ joins the router farm
#                              (niri wrappers + nix-backed pkg shims).
#
# The router (bin/omarchy) locates sibling commands via
#   OMARCHY_BIN_DIR=$(dirname "$BASH_SOURCE[0]")
# and resolves data via OMARCHY_PATH, so consumers must set
#   environment.sessionVariables.OMARCHY_PATH = "${omarchy}/share/omarchy";
assert compositor == "hyprland" || compositor == "niri";
stdenvNoCC.mkDerivation {
  pname = "omarchy";
  version = lib.removeSuffix "\n" (builtins.readFile "${src}/version");

  src = lib.cleanSource src;

  installPhase = ''
    runHook preInstall

    runtime_root="$out/share/omarchy"
    mkdir -p "$runtime_root" "$out/bin"

    # Runtime trees (mirror upstream's /usr/share/omarchy layout).
    for tree in bin themes shell config default applications manual install migrations; do
      if [ -d "$tree" ]; then
        cp -r "$tree" "$runtime_root/"
      fi
    done
    if [ -f version ]; then
      cp version "$runtime_root/version"
    fi
    # Branding assets resolved via $OMARCHY_PATH/<file> by omarchy-show-logo,
    # omarchy-branding-about / -screensaver, plus the PNG/SVG that default/
    # symlinks (default/chromium/extensions/*/icon.png -> ../../../../icon.png)
    # resolve against.
    for asset in logo.txt icon.txt icon.png logo.svg; do
      [ -f "$asset" ] && cp "$asset" "$runtime_root/$asset"
    done

    # Additive Niri layer. shell-niri/ mirrors shell/'s relative layout, so a
    # straight copy overlays the niri variants; bin-niri/ joins the bin farm.
    if [ "${compositor}" = "niri" ]; then
      if [ -d shell-niri ]; then
        cp -r shell-niri/. "$runtime_root/shell/"
      fi
      if [ -d bin-niri ]; then
        cp -r bin-niri/. "$runtime_root/bin/"
      fi
    fi

    # Symlink farm: bin/omarchy + every bin/omarchy-* onto PATH. The router
    # resolves OMARCHY_BIN_DIR from its own realpath, so symlinking (rather
    # than wrapping) keeps its dirname = $runtime_root/bin, where the sibling
    # commands actually live.
    for f in "$runtime_root/bin/omarchy" "$runtime_root/bin/omarchy-"*; do
      [ -e "$f" ] || continue
      ln -s "$f" "$out/bin/$(basename "$f")"
    done

    runHook postInstall
  '';

  meta = with lib; {
    description = "Omarchy UX layer — themes, router, plugins, shell, dots (Reverb-OS downstream fork)";
    homepage = "https://github.com/reverb256/omarchy";
    license = licenses.mit;
    mainProgram = "omarchy";
    platforms = platforms.linux;
  };
}
