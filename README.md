# Karui Oto — ephemeral fzf pickers for MPD

Keyboard-driven pickers for MPD: songs, artists, albums and folders in
minimal floating windows. Pick one and it plays instantly, the rest
shuffles behind it.

On-demand philosophy: **0 boot processes** — MPD starts on the first pick
and `Mod+X` (or `kill`) takes everything down. Esc with nothing playing
shuts down too.

## Quick start

```sh
git clone https://github.com/Adoyoh/karui-oto.git && cd karui-oto
./install.sh --dry-run   # see what it would do
./install.sh             # actually install
karui-oto setup          # wizard: music dir, terminal, shortcuts
```

Press your shortcut, pick, listen. Edit `shortcuts{}`, save, and the next
keypress already works (binds self-sync in the background).

## Requirements

| Required | For | Notes |
|---|---|---|
| `mpd` | the music daemon (your current config works) | tested 0.24 |
| `mpc` | CLI against MPD | tested 0.24 |
| `fzf` | the pickers | recent (~2024+; `install.sh` checks `--accept-nth`) |
| `bash`, `coreutils`, `grep` | everyday shuf/sort/awk | |
| `python3` (stdlib) | parses `config.jsonc` (vendored, auditable) | |
| `kitty` **or** `foot` | the picker window (`terminal`) | full flag parity |

| Optional | For | If missing |
|---|---|---|
| `mpdris2` | MPRIS (see what's playing in your bar) | `"mpris": false` |
| `playerctl` | media keys (`karui-media`) | MPD-only control |
| Nerd Font | icons (magnifier, pointer) | plain ASCII in `icons` |
| `mutagen` (python) | one-shot retag utility | not runtime |

## Installation (nothing touches your `.bashrc`)

1. Copies the tree to `~/.local/share/karui-oto/` + symlinks in `~/.local/bin/`.
2. Creates `~/.config/karui-oto/config.jsonc` **only if missing** (never overwritten).
3. Prints what to paste into your compositor (see `binds/`: niri, hyprland).

Alternatives: clone to `~/apps/` and use absolute paths in the binds (zero
installation), or manual symlink. Uninstall: `./uninstall.sh [--purge] [comp]`
(also removes our compositor binds with backup; your own binds stay).
If `~/.local/bin` is not on your `PATH`, it tells you but **you add it**.

## Daily use

| Command | Does |
|---|---|
| `karui-oto songs` / `artists` / `albums` / `folders` | open that picker (usually via shortcut) |
| `karui-oto kill` | stop everything, drop the daemon (0 processes) |
| `karui-media next\|prev\|play-pause` | media keys (MPD first, throttled) |
| `karui-oto setup` | interactive wizard (writes `config.jsonc`) |
| `karui-oto doctor` | health check: deps, config, binds, drift (offers one-time install) |
| `karui-oto binds [comp]` | print the snippet; `--copy`, `--apply`, `--remove`, `--sync` |

## Shortcuts (`shortcuts` + `karui-oto binds`)

Shortcuts live in your compositor but are **generated** from the config:
the `"shortcuts"` block starts empty (unassigned); set your combos
(`Mod+O`, `Mod+Shift+P`; empty string = unassigned):

```sh
karui-oto binds            # autodetects niri|hyprland
karui-oto binds hyprland   # or explicit
karui-oto binds --copy     # to clipboard (or warns if no wl-copy/xclip)
```

No manual apply needed: every picker run reconciles your `shortcuts{}`
with the compositor in a background subshell (backup + marked block,
`--remove` reverts). Edit the jsonc, save, and the next keypress works
(the keypress that triggers the sync still behaves the old way, once).
`karui-oto binds --apply` still exists for manual installs with confirmation.

Per-compositor shortcuts: each DE keeps its own binds. `shortcuts{}` is
the default for both; optional `shortcuts_niri{}` / `shortcuts_hyprland{}`
sections override per mode (absent section = inherit globals, empty mode =
unassigned there). Assigning in one compositor never wipes the other.
Switching to a compositor with no karui blocks yet? `doctor` offers the
one-time install ([y/N]); or run `karui-oto binds --sync <comp>` once.

Each compositor has its own syntax — same shortcut (`songs` = `Mod+O`):

```kdl
# niri (inside binds {}):
Mod+O hotkey-overlay-title="karui-oto: search song" { spawn "bash" "-c" "~/.local/bin/karui-oto songs"; }
```
```lua
-- hyprland.lua (>= 0.55, Lua; legacy hyprland.conf below for older).
-- Paths go absolute because Lua exec_cmd does not expand ~:
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("/home/you/.local/bin/karui-oto songs"))
```
```ini
# hyprland.conf (legacy, < 0.55):
bind = $mainMod, O, exec, ~/.local/bin/karui-oto songs
```

Paste the output into your compositor. `binds/` holds full examples.
Supported: niri and hyprland (other desktops were cut; git history keeps
their translators in case they ever return).

## Configuration (`~/.config/karui-oto/config.jsonc`)

JSONC (JSON with `//` and `/* */`, like fastfetch). Everything commented
with defaults in `config.jsonc.example`, in code order. Essentials:

| Key | Effect |
|---|---|
| `terminal` = kitty\|foot | which `terminals/` adapter opens the picker |
| `path`, `mpd_conf` | your music and your mpd (`~` expands, both must exist) |
| `kitty` / `foot` (sections) | per-terminal config: `font`, `font_size`, `width`, `height`, `color`, `transparency` |
| `color` | `"#rrggbb"` = background + auto-contrast text; `""` = default |
| `transparency` | 0.00–1.00 validated (kitty: background only; foot: whole window, washes text out below 1.0) |
| `font`, `font_size` | fontconfig family (warns if missing, cached 24h) + points |
| `theme` + `icons` section | palette (`themes/yours.sh`) and search/arrow/marker/album glyphs |
| `shuffle`/`repeat` | `random`/`repeat` on/off — global |
| `mpris` | deferred mpDris2 after picking (or never) — global |
| `modes` | per-bind overrides: `songs`/`artists`/`albums`/`folders` with their own `shuffle`/`repeat`/`mpris`; `""` = inherit global |
| `shortcuts_niri` / `shortcuts_hyprland` | per-compositor overrides (absent = inherit `shortcuts{}`) |
| `term_class` | window app-id for compositor rules (letters, digits, `_.-` only) |
| `min_tracks` | artists mode: hide artists with fewer tracks (1 = show all) |
| `logo` | picker logos (kitty-only for images): `symbol` items (text/emoji in the header, with `color`/`size`/`position`) or one `image` (kitty window logo with perceptual `transparency`/0–100 `size`/9-point `position`/`color`=tint); `gif` unsupported, 1 image max, ignored on foot |
| `hide` | regex array filtered out of artists mode (each must compile) |

Unknown key = warning (likely typo). Invalid value = fatal with message
and offending lines. The `logo` image path must exist.

One-off overrides without touching the file (tests, aliases):
`KARUI_OTO_CONFIG=/path/other.jsonc` (another config) and
`KARUI_OTO_TERMINAL=foot` (another terminal with your real config).

## Doctor (`karui-oto doctor`)

Read-only health check (except one consented write, see below):

| # | Check |
|---|---|
| 0 | Config parses and validates (syntax errors shown with lines + hints) |
| 1 | Hard deps: bash, mpc, mpd, fzf, python3 (+ `--accept-nth`), terminal |
| 2 | Optionals, never fatal: mpDris2, playerctl |
| 3 | MPD alive + non-empty library (down is normal: on-demand) |
| 4 | Non-empty music dir + installed font |
| 5 | Binds per mode (installed/conflict/missing), media keys 3/3, drift vs `shortcuts{}` |
| 6 | Logo setup (symbols/images, foot caveat, PIL tint backend) |

Plus: stale `xdg-desktop-portal-gnome` warning (it stalls portal requests
~25s without GNOME Shell — not a karui-oto bug), and the interactive
one-time install offer when the current compositor has no karui blocks
yet (`[y/N]`, backup + validation; piped runs only print the fix).

## Shells and fonts

Works **from any shell** (bash, zsh, fish, dash): scripts carry a
`#!/bin/bash` shebang (always run in bash) and aliases are POSIX. Nothing
to configure per shell.

Fonts resolve through fontconfig (`~/.fonts`,
`~/.local/share/fonts`, `/usr/share/fonts`, ...): drop your `.ttf/.otf`
there and check with `fc-match "Name"`. Startup warns if your `font` is
missing (with fallback); the default (Liberation Mono) is only advisory.

## Library conventions

- **Artists:** by `artist`+`albumartist` tags (any layout works: loose
  singles, one folder with everything). `X feat. Y` shows under X **and** Y;
  `min_tracks` (default 1 = show all; 2 hides one-track guests). Tidy users:
  `folders` mode.
- **Songs/albums:** by tags (`artist/album/title`; `%artist%` shows the
  first value of multi-tags). Ambiguous albums ("Greatest Hits") disambiguate
  by artist (exact album+artist find).
- **Folders:** any subtree as-is (`Artist/[Year] Album` straight through).

## Troubleshooting (known quirks, not pending bugs)

- `mpc playlist` prints `Artist - Title`, **not paths**: never locate a
  track by grepping the playlist (see `lib/picker.sh`).
- `mpc insert` appends **at the end** on mpd 0.24/mpc 0.24 (the man page
  says after current): the code never depends on position.
- `mpc listall -f` **ignores** the format: the tagged list comes from
  `mpc search -f ... title ""` (matches all, ~0.3s on 5k tracks).
- Bare `mpc play` with random on starts anywhere: always `play <N>`.
- Kitty takes ~25s to open / GTK dialogs hang on Hyprland or Niri:
  usually `xdg-desktop-portal-gnome` without GNOME Shell (stalls the
  Settings and FileChooser portals). Not a karui-oto bug (`doctor`
  warns): `sudo apt remove xdg-desktop-portal-gnome` (Nautilus is
  unaffected, it uses libportal). Measured effect: kitty 26.5s → ~1s.
- Changed `shortcuts{}` but keys still run the old command? The sync heals
  it on the next picker run (`doctor` shows drift meanwhile). Fresh
  compositor with no binds at all? `doctor` offers the one-time install.
