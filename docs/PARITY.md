# Omarchy Niri Port — Full Parity + DE Switching (upstreamable by design)

> This fork exists because upstream's stance is "we will not be implementing
> Niri". We respect that — this is a fork, not a pressure campaign. But the
> fork is **always capable of being upstreamed**: upstream files stay
> pristine, every adaptation is additive and opt-in, and the Hyprland
> experience is byte-identical to upstream. If upstream ever changes its
> mind, merging this layer is a clean rebase + merge, not a rewrite.

## The upstreamable contract (rules that keep this mergeable upstream)

1. **Never modify an upstream file in place.** All Niri adaptation lives in
   additive trees: `shell-niri/`, `bin-niri/`, `config-niri/`,
   `themes/*/niri.kdl`. A sync from upstream must be a *near-clean rebase*.
2. **Zero-config for Hyprland users.** With `OMARCHY_COMPOSITOR=hyprland`
   (the default) the fork is byte-identical to upstream — same bin farm,
   same shell, same config. Nothing niri-related is installed or executed.
3. **Selection is explicit and env-driven.** `OMARCHY_COMPOSITOR=niri`
   gates the additive layer at build time (which trees ship) and at runtime
   (which commands/autostarts run). No heuristics, no "detect the WM".
4. **No Reverb-OS-specific content in the fork.** The fork's flake, module,
   and options are generic (`programs.omarchy.compositor`); the cluster's
   specific wiring lives in nixos-config and consumes this fork as an input.
5. **CI gates every sync.** `niri-gate` builds both variants +
   quickshell-niri and fails on shell-niri drift (a variant file with no
   upstream counterpart means upstream moved the QML and we drifted).
6. **Config is generated, not hand-edited.** Niri config fragments live as
   source in the repo and are assembled (at Nix build time for the flake
   path). No "edit config.kdl after install" workflow.

## Parity matrix (Hyprland → Niri)

### Compositor IPC (25 upstream `omarchy-hyprland-*` commands)

| Upstream command | Niri equivalent (bin-niri/) | Status |
|---|---|---|
| `omarchy-hyprland-window-close-all` | `niri msg -j windows` → `action close-window --id` per id → `focus-workspace 1` | ✅ shipped |
| `omarchy-hyprland-focus-app` | `niri msg action focus-window --id` via `niri msg -j windows` match on app_id | todo |
| `omarchy-hyprland-monitor-*` (10 cmds) | `niri msg -j outputs` / `focused-output` (name/scale/logical-size) | todo |
| `omarchy-hyprland-session-locked` | `niri msg -j` state / swaylock wrapper | todo |
| `omarchy-hyprland-toggle` / `-disabled` / `-enabled` | niri has no toggles — absent features, wrappers report unsupported | document |
| `omarchy-hyprland-window-gaps-toggle` / `-pop` / `-transparency-toggle` | **no niri equivalent** (per jeremy/omarchy-niri: don't fake what doesn't exist) | document |
| `omarchy-hyprland-window-single-square-aspect-toggle` | `set-column-width`/height presets | todo |
| `omarchy-hyprland-window-tiled-fullscreen-toggle` | `maximize-column` / `fullscreen-window` | todo |
| `omarchy-hyprland-window-width` | `set-column-width` / `set-window-height` | todo |
| `omarchy-hyprland-workspace-layout-toggle` | niri scrollable layout — no toggle; document | document |
| `omarchy-hyprland-reload-guard` / `-refresh-hyprland` | no reload in niri; restart swaybg (see services) | document |

### Shell (Quickshell QML)

| Upstream file | shell-niri/ variant | Status |
|---|---|---|
| `shell/plugins/bar/widgets/Workspaces.qml` | `import Niri` + `Niri.workspaces` model | ✅ shipped |
| `shell/plugins/bar/widgets/KeyboardLayout.qml` | Niri input API | ✅ shipped |
| `shell/plugins/bar/Bar.qml` | layer-shell identical; drop Hyprland-only bits | ✅ shipped |
| `shell/plugins/services/idle/Service.qml` | niri idle (swayidle-backed) | ✅ shipped |
| `shell/Ui/PopupCard.qml` | Niri workspace focus calls | ✅ shipped |
| `shell/Commons/Style.qml` | theme color source (Hyprland-free) | ✅ shipped |

### Keybindings

Full map in `config-niri/bindings.kdl` (adapted from okimarchy's tested map):
`Mod+1..9` workspaces, `Mod+Shift+1..9` move-column-to-workspace,
`Mod+arrows` column/window focus, `Alt+Tab` → focus-window-down/up,
`Mod+T/F/Ctrl+F/R` layout, `Mod+Minus/Equal` resize, `Mod+W` close,
`Mod+Shift+Q` quit, `Mod+Wheel` workspace scroll, media via swayosd.

### Services (idle/lock/nightlight/wallpaper/picker/OSD/portal)

| Hyprland | Niri | Package |
|---|---|---|
| hypridle | swayidle | `swayidle` |
| hyprlock | swaylock (effects) | `swaylock` |
| hyprsunset | wlsunset | `wlsunset` |
| hyprpaper | swaybg | `swaybg` |
| hyprpicker | grim + slurp + imagemagick | `grim` `slurp` |
| omarchy OSD | swayosd | `swayosd` |
| xdg-desktop-portal-hyprland | xdg-desktop-portal-gtk/gnome | `xdg-desktop-portal-gtk` |
| (niri) | xwayland-satellite | `xwayland-satellite` |

### Session

- Both WMs run under **uwsm** sessions (`hyprland-uwsm` / `niri-uwsm`), so
  the SDDM session picker offers both and autologin is a one-line swap —
  same mechanism zephyr already uses for niri.
- The shell starts via the WM's autostart: Hyprland via
  `default/hypr/apps/omarchy-shell.lua` + exec; Niri via a
  `spawn-at-startup "quickshell -c …/shell/shell.qml"` fragment. Layer
  rules that exist only in Hyprland (no_anim) simply don't apply on niri —
  niri has no layer fade animations by default, so behavior is equivalent.

### Theming

Per-theme Niri colors: each theme ships `themes/<name>/niri.kdl` (layout,
focus-ring, border, shadow — okimarchy's pattern), generated into the
active config last so theme colors win. Stylix integration (Reverb-OS)
drives these from the same palette source as the Hyprland side.

## DE switching design

1. **Build-time (declarative)**: `programs.omarchy.compositor =
   "hyprland" | "niri"` selects which additive trees ship and sets
   `OMARCHY_COMPOSITOR` for the session. This is the Nix-native switch:
   a config change + rebuild, generation rollback = WM rollback.
2. **Runtime (both installed)**: install both variants, SDDM offers
   `Hyprland (uwsm)` and `Niri (uwsm)` sessions; `omarchy-wm-switch`
   (adapted from okimarchy) = regenerate session config + set autologin +
   reboot. `$OMARCHY_COMPOSITOR` gates which bin-niri/ wrapper set is
   active in-session.

## Build roadmap

- [x] Fork + additive shell-niri/ (6 QML variants) + bin-niri/ pkg shims
- [x] Flake: `omarchy`, `omarchy-niri`, `quickshell-niri`, overlay, module
- [x] CI gate (build both variants + drift check)
- [ ] bin-niri/ full wrapper farm (IPC parity, 12 todo rows above)
- [ ] `config-niri/` modular KDL + bindings map + autostart (shell launch)
- [ ] Per-theme `niri.kdl` (theming parity)
- [ ] Service parity wiring (idle/lock/nightlight/wallpaper/picker/OSD/portal)
- [ ] `omarchy-wm-switch` runtime switcher
- [ ] VM tests: boot Hyprland variant + Niri variant (QEMU/microVM), verify
      shell QML loads with zero errors, screenshot both
- [ ] Re-wire nixos-config to the fork (Stage 2)
