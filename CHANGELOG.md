# CHANGELOG — format: `## [version] - date` (newest on top)

## [1.1.0] - 2026-10-02
- BREAKING: compositors cut to niri + hyprland (sway/i3/openbox/bspwm and
  the gnome/kde/xfce/cinnamon/mate live backends removed; git history
  keeps them). All lists, docs and examples updated.
- Auto-sync: every picker run reconciles shortcuts{} into the compositor
  in the background after opening (~1ms fork on the critical path, work
  while you browse). Edit + save = working from the next keypress; no
  manual --apply needed. Fail-open: sync never blocks the picker.
  Unclosed marker ranges warn instead of deleting to EOF.
- Validation gaps closed: unknown section subkeys die in jconfig
  (icons/kitty/foot/shortcuts), term_class charset restricted (app-id
  safe), every hide[] pattern must compile (indexed error).
- Foot transparency default 1.0 -> 0.85 (whole-window alpha; example updated).
- karui-media snappier: THROTTLE 0.5s -> 0.25s (gap runs post-order under
  lock, single presses never delayed), hung-bridge timeout 5s -> 2s.
  KARUI_MEDIA_THROTTLE override unchanged as instant rollback.
- Lock-takeover race hardened (loser drops the press instead of doubling).
- Sync reloads dismiss Hyprland-internal popups (pre-existing config
  notices are not ours); notification centers untouched.
- doctor warns about xdg-desktop-portal-gnome without GNOME Shell (static
  dpkg check, never probed: it stalls portal requests ~25s).
- Hyprland >= 0.55 (Lua): autodetect hyprland.lua vs legacy hyprland.conf,
  Lua emitters (binds + media with locked+repeating), Lua-aware conflict
  scan, live validate (hyprctl reload + configerrors, auto-restore).
  Missing config = guided fallback, never a fatal "not found".
- Floating picker rules installed always with the binds (same backup):
  niri open-floating + fixed size (top-level window-rule), hyprland float +
  90% + center (Lua window_rule / legacy windowrule). Own marked section,
  --remove and uninstall.sh strip both blocks.
- Setup/doctor UX: explicit "program installed OK" vs "binds pending"
  status lines; doctor reports the hyprland variant in use.
- Desktop support beyond tiling WMs: gnome/kde/xfce/cinnamon/mate
  (gsettings/kwriteconfig/xfconf backends with backup + conflict check),
  openbox (rc.xml <keyboard> insert) and bspwm (sxhkdrc). New translators
  (gnome/kde/openbox/sxhkd keys), per-target validators (niri validate,
  i3 -C, others print manual reload), managed /nix/store files refused.
  New binds/ examples + COMPATIBILITY.txt matrix.
- Plain-English reassurance under the --apply safety line ("This installs
  your shortcuts so the pickers open with your keys...").
- `min_tracks` default 2 -> 1 (show all; single-song artists were hidden).
  Setup prompt now hints (1 = show all, 2 = hide one-track guests).
- Music dir default autodetects (XDG music dir, then ~/Música, ~/Music,
  ~/music, ~/Musica): English home folders work out of the box.
- `uninstall.sh` also removes our compositor binds (marked block / karui-oto
  entries, backup first): detected desktop plus a sweep of any other config
  still holding our block; `[comp]` limits to one desktop.
- karui-media throttled anti-spam: serialized orders with a 0.5s gap
  (KARUI_MEDIA_THROTTLE override), extras dropped never queued (spamming
  used to pile orders onto mpDris and crash it), atomic lockdir + stale
  takeover, playerctl bounded with timeout.
- Media keys fixed + hardened: the generator now emits the 3 real XF86 lines
  on all 11 targets (before, --apply never installed them: the likely cause
  of dead media keys), karui-media prefers mpd (playerctl -p mpd, then mpc
  fallback, never another player), stale-safe lockfile, preflight warns
  (never blocks) on foreign XF86 binds, doctor checks media 3/3.
- Per-mode overrides (`modes.<mode>.{shuffle,repeat,mpris}`): each bind can
  carry its own behavior, empty inherits the global from setup. Strict
  validation (unknown mode/key or non-boolean = fatal with message),
  setup roundtrips customs untouched, effective values resolved per pick.
- Logo section (`logo[]`, kitty-only for images): unlimited mixed symbol
  (header text with color/size/position, any terminal) and one window image
  (native alpha/scale/9-point position, optional tint via cached PIL chain,
  graceful fallback without it). gif rejected, 2+ images fatal, foot warns
  and keeps symbols. Setup roundtrips, doctor reports effective state.
- `expand_tilde`: `~/Música` typed in setup is accepted (was rejected).
- Per-compositor bind examples in README (niri/hyprland/sway/i3).
- Artists mode back on TAGS (folders only fit tidy libraries): list =
  artist+albumartist values + conservative feat-split (`X feat. Y` listed
  under BOTH, never splitting band names like AC/DC), `min_tracks` knob
  (default 2 hides one-track guests), queue = exacts + word-boundary feats.
- `setup` offers to apply binds right away (consent+backup flow).
- `folders` mode: pick any subtree (`Artist/[Year] Album` direct), same
  queue semantics as artists + `SHORTCUTS_FOLDERS` + binds everywhere.
  LICENSE holder: Adoyoh.
- Full-English schema: keys/values (`width/height/theme/icons/search/arrow/
  marker/shuffle/repeat/hide/transparency`), active-empty `shortcuts.*`
  (uncommented block removed: empty = unassigned, no comma dance).
- 100% English codebase + config (comments, messages, example, user config).
- `shortcuts.*` section (all commented = unassigned): fill combos and run
  `karui-oto binds [niri|hyprland|sway|i3]` (autodetects) to generate
  compositor lines. Canonical `Mod+O` form, validated; translators per
  compositor ($mainMod/$mod aware, XF86-safe).
- Per-terminal `kitty`/`foot` config sections (font, size, geometry, color
  and transparency each; `terminal` picks which opens). Validated ranges;
  auto contrast for `color`.
- Config migrated to JSONC (`config.jsonc`, fastfetch-style): `path`,
  `color` (+auto contrast), `transparencia_kitty/foot` (validated range),
  `ancho/alto`, `font/font_size`, pasteable `iconos` section, `aleatorio`,
  `repetir`, `mpris`, `ocultar[]`. Own stdlib parser (`lib/jconfig.py`);
  python3 becomes a hard dep. Old bash format removed (pre-release, free).

## [1.0.0] - 2026-09-26
Primera versión compartible. Fusiona los scripts sueltos en CLI único.
- Modos: songs (tags), artists (carpetas), albums (tags agrupados), kill.
- Config en `~/.config/karui-oto/`: colores, fuente, shuffle/repeat,
  MPRIS, terminal (kitty/foot), iconos, exclusiones.
- Snippets de binds: niri, hyprland, sway, i3. Teclas multimedia aparte.
- install.sh honesto (dry-run, sin tocar dotfiles) + uninstall.sh.
- Esc inteligente (cierra solo con música; mata todo sin nada sonando).
- Documentados los quirks de mpc/mpd que nos mordieron (ver README).
