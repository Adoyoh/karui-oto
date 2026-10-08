#!/bin/bash
# ============================================================================
# karui-oto · tests/smoke.sh — minimal committed test suite
# ----------------------------------------------------------------------------
# WHAT:
#   Fast, non-interactive regression net (no compositor, no MPD, no network).
#   Everything runs against fixture files under a temp dir; the user's live
#   config and sessions are never touched (XDG_CONFIG_HOME + KARUI_OTO_CONFIG
#   overrides). Run: ./tests/smoke.sh (exit 0 = all green).
#
# COVERS:
#   jconfig parse (valid/broken/unknown keys), validate() rejections,
#   drift matrix (orphan/missing/in-sync), binds print (niri + hyprland),
#   sync idempotency + --remove roundtrip on fixtures.
# ============================================================================
set -u

ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
export KO_ROOT="$ROOT"
# shellcheck disable=SC1091
source "$KO_ROOT/lib/common.sh"
source "$KO_ROOT/lib/binds.sh"
source "$KO_ROOT/lib/bindsinstall.sh"
source "$KO_ROOT/lib/screens.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/home"
mkdir -p "$XDG_CONFIG_HOME/hypr"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'NOT OK: %s\n' "$1"; }

# --- fixture config (valid, two shortcuts) ----------------------------------
cat > "$T/config.jsonc" << 'EOF'
{
  "path": "/tmp",
  "mpd_conf": "/tmp/ko-test-mpd.conf",
  "terminal": "foot",
  "term_class": "buscador_mpd",
  "kitty": { "font": "Liberation Mono", "font_size": 16, "width": 95, "height": 15, "color": "", "transparency": 0.85 },
  "foot": { "font": "Liberation Mono", "font_size": 16, "width": 100, "height": 24, "color": "", "transparency": 0.85 },
  "theme": "karui-dark",
  "icons": { "search": "", "arrow": "", "marker": "", "album": "", "folder": "" },
  "shuffle": true,
  "repeat": true,
  "mpris": false,
  "min_tracks": 1,
  "hide": [],
  "shortcuts": { "songs": "Mod+O", "artists": "", "albums": "", "folders": "", "kill": "Mod+X" },
  "modes": {},
  "logo": []
}
EOF
touch /tmp/ko-test-mpd.conf
export KARUI_OTO_CONFIG="$T/config.jsonc"

# 1. jconfig parses the valid fixture.
if python3 "$KO_ROOT/lib/jconfig.py" "$T/config.jsonc" >/dev/null 2>&1; then
    ok "jconfig parses valid config"
else
    bad "jconfig rejects valid config"
fi

# 2. jconfig rejects trailing comma / unknown key.
sed 's/"kill": "Mod+X"/"kill": "Mod+X",/' "$T/config.jsonc" > "$T/bad-comma.jsonc"
if python3 "$KO_ROOT/lib/jconfig.py" "$T/bad-comma.jsonc" >/dev/null 2>&1; then
    bad "jconfig accepts trailing comma"
else
    ok "jconfig rejects trailing comma"
fi
sed 's/"songs": "Mod+O"/"songz": "Mod+O"/' "$T/config.jsonc" > "$T/bad-key.jsonc"
if python3 "$KO_ROOT/lib/jconfig.py" "$T/bad-key.jsonc" >/dev/null 2>&1; then
    bad "jconfig accepts unknown shortcut subkey"
else
    ok "jconfig rejects unknown shortcut subkey"
fi

# 3. validate() accepts good, rejects bad term_class + bad hide regex.
if load_config >/dev/null 2>&1; then
    ok "validate accepts fixture"
else
    bad "validate rejects fixture"
fi
(
    TERM_CLASS="con espacios"
    validate >/dev/null 2>&1
) && bad "validate accepts bad term_class" || ok "validate rejects bad term_class"
(
    HIDE=$'^(unclosed'
    validate >/dev/null 2>&1
) && bad "validate accepts bad hide regex" || ok "validate rejects bad hide regex"

# 4. canonical combos (shared by setup + validate).
for c in "Mod+O" "Mod+Shift+P" "F12" "XF86AudioPlay"; do
    combo_canonical_ok "$c" && ok "canonical accepts $c" || bad "canonical rejects $c"
done
for c in "mod+o" "C" ""; do
    combo_canonical_ok "$c" && bad "canonical accepts [$c]" || ok "canonical rejects [${c:-EMPTY}]"
done

# 5. drift matrix on a fixture hyprland.lua (legacy branch: no hyprland
# binary involved since only the .conf exists... use .lua absent + .conf
# present to force the legacy path deterministically).
printf 'bind = $mainMod, O, exec, ~/.local/bin/karui-oto songs\n' > "$XDG_CONFIG_HOME/hypr/hyprland.conf"
if binds_drift hyprland >/dev/null 2>&1; then
    bad "drift misses legacy Mod+O songs bind"
else
    ok "drift sees installed legacy bind (rc=1 means differences found)"
fi
# NOTE: rc=1 above is correct: fixture lacks media keys + rules, so drift
# must report. The assertion is that it DETECTS (rc!=0), not that clean.

# 6. binds print renders both targets.
karui_prints_ok=1
gen_binds_block niri | grep -q "karui-oto songs" || karui_prints_ok=0
gen_binds_block hyprland | grep -q "karui-oto" || karui_prints_ok=0
gen_rules_block niri | grep -q "buscador_mpd" || karui_prints_ok=0
gen_rules_block hyprland | grep -q "buscador_mpd" || karui_prints_ok=0
[ "$karui_prints_ok" -eq 1 ] && ok "binds+rules print for niri+hyprland" || bad "binds/rules print broken"

# 7. sync idempotency + remove roundtrip on the fixture (legacy conf: no
# live checker involved, pure file mechanics + markers).
if binds_sync hyprland >/dev/null 2>&1; then
    grep -qF -- "$(mark_open hyprland)" "$XDG_CONFIG_HOME/hypr/hyprland.conf" \
        && ok "sync installs marked block" \
        || bad "sync installed nothing"
else
    bad "sync failed on fixture"
fi
# NOTE: the hand-written legacy line above is NOT in a marked block, so the
# tool (by safety contract) never deletes it: stray lines stay, marked
# content roundtrips. Idempotency therefore means: second sync changes
# nothing (same line count), remove strips every marked line.
if binds_sync hyprland >/dev/null 2>&1; then
    _n1="$(grep -c "karui-oto" "$XDG_CONFIG_HOME/hypr/hyprland.conf")"
    binds_sync hyprland >/dev/null 2>&1
    _n2="$(grep -c "karui-oto" "$XDG_CONFIG_HOME/hypr/hyprland.conf")"
    [ "$_n1" -eq "$_n2" ] \
        && ok "re-sync is idempotent (line count $_n1 -> $_n2)" \
        || bad "re-sync changed line count ($_n1 -> $_n2)"
else
    bad "re-sync failed on fixture"
fi
remove_block hyprland "$XDG_CONFIG_HOME/hypr/hyprland.conf"
if grep -qF -- "$(mark_open hyprland)" "$XDG_CONFIG_HOME/hypr/hyprland.conf" \
    || grep -qF -- "$(mark_open_rules hyprland)" "$XDG_CONFIG_HOME/hypr/hyprland.conf"; then
    bad "remove left marked blocks behind"
else
    ok "remove strips all marked blocks (hand lines stay by design)"
fi

# 8. font-colors: unknown subkey dies; valid keys apply in isolation
# (others byte-identical); bad values die with the config spelling.
printf '{\n  "font-colors": {\n    "nope": "#112233"\n  }\n}\n' > "$T/fc-bad.jsonc"
if python3 "$KO_ROOT/lib/jconfig.py" "$T/fc-bad.jsonc" >/dev/null 2>&1; then
    bad "jconfig accepts unknown font-colors subkey"
else
    ok "jconfig rejects unknown font-colors subkey"
fi
C_ARTIST="A"; C_ALBUM="B"
FZF_COLOR="border:#111111,scrollbar:#222222"
FC_SCROLLBAR="#00ff00"; FC_BORDER_LABEL="#ff0000"; FC_GUTTER=""
export C_ARTIST C_ALBUM FZF_COLOR FC_SCROLLBAR FC_BORDER_LABEL FC_GUTTER
apply_font_colors
[ "$C_ARTIST" = "A" ] && [ "$C_ALBUM" = "B" ] \
    && ok "font-colors leaves text colors alone unless set" \
    || bad "font-colors clobbered text colors"
case "$FZF_COLOR" in
    "border:#111111,scrollbar:#00ff00,border-label:#ff0000")
        ok "font-colors patches fzf keys in isolation" ;;
    *) bad "font-colors fzf patch wrong: [$FZF_COLOR]" ;;
esac
(
    FC_BORDER_LABEL="zzz"
    validate >/dev/null 2>&1
) && bad "validate accepts bad font-colors value" \
  || ok "validate rejects bad font-colors value"

# 9. rules_px: cells x font metrics -> pixels (spot values hand-computed:
# 100x24@16+8 = 976x496; 125x34@16+8 = 1216x696; defaults are integers).
# 10. stale rules: markers present but content differs (e.g. width/height
# edited after install) must report drift so the next sync regenerates.
[ "$(WIDTH=100 HEIGHT=24 FONT_SIZE=16 WIN_PAD=8 rules_px)" = "976 496" ] \
    && ok "rules_px 100x24 -> 976 496" \
    || bad "rules_px 100x24 wrong: [$(WIDTH=100 HEIGHT=24 FONT_SIZE=16 WIN_PAD=8 rules_px)]"
[ "$(WIDTH=125 HEIGHT=34 FONT_SIZE=16 WIN_PAD=8 rules_px)" = "1216 696" ] \
    && ok "rules_px 125x34 -> 1216 696" \
    || bad "rules_px 125x34 wrong"
_rpx="$(rules_px)"
case "$_rpx" in
    ''|*[!0-9\ ]*) bad "rules_px defaults not integers: [$_rpx]" ;;
    *) ok "rules_px defaults integers: [$_rpx]" ;;
esac
# gen_rules_block carries the derived numbers (niri + hyprland legacy).
WIDTH=100 HEIGHT=24 FONT_SIZE=16 WIN_PAD=8 TERM_CLASS="buscador_mpd_test"
export WIDTH HEIGHT FONT_SIZE WIN_PAD TERM_CLASS
gen_rules_block niri | grep -q "fixed 976" \
    && ok "niri rules carry derived width" \
    || bad "niri rules missing derived width"
XDG_CONFIG_HOME="$T/home" gen_rules_block hyprland 2>/dev/null | grep -q "976" \
    && ok "hyprland rules carry derived numbers" \
    || bad "hyprland rules missing derived numbers"

# 10. stale rules content (markers present, numbers from other dims)
# reports drift; identical content is clean.
mkdir -p "$T/stale/hypr"
printf -- '-- >>> karui-oto rules >>>\n%s\n-- <<< karui-oto rules <<<\n' \
    'hl.window_rule({ float = true, })' > "$T/stale/hypr/hyprland.lua"
WIDTH=100 HEIGHT=24 FONT_SIZE=16 WIN_PAD=8 TERM_CLASS="buscador_mpd_test" \
XDG_CONFIG_HOME="$T/stale" binds_drift hyprland 2>&1 | grep -q "stale: window rules" \
    && ok "drift flags stale rules content" \
    || bad "drift misses stale rules content"

rm -f /tmp/ko-test-mpd.conf

# 11. screens: cells_for_screen spot values (~75% coverage).
[ "$(cells_for_screen 1366x768)" = "105 28" ] \
    && ok "cells 768p -> 105 28" \
    || bad "cells 768p wrong: [$(cells_for_screen 1366x768)]"
[ "$(cells_for_screen 1920x1080)" = "148 40" ] \
    && ok "cells 1080p -> 148 40" \
    || bad "cells 1080p wrong"
[ "$(cells_for_screen 1600x900)" = "123 33" ] \
    && ok "cells 900p -> 123 33" \
    || bad "cells 900p wrong"
[ "$(cells_for_screen 2560x1440)" = "198 53" ] \
    && ok "cells 2k -> 198 53" \
    || bad "cells 2k wrong"
[ "$(cells_for_screen 3840x2160)" = "298 80" ] \
    && ok "cells 4k -> 298 80" \
    || bad "cells 4k wrong"
[ "$(cells_for_screen 320x200)" = "40 10" ] \
    && ok "cells tiny clamps to floors" \
    || bad "cells floors wrong"

# 12. detect_screen tiers via fixture sysfs (KO_SYSFS_DRM).
mkdir -p "$T/drm/card0-eDP-1" "$T/drm/card0-HDMI-1"
printf 'connected' > "$T/drm/card0-eDP-1/status"
printf '1366x768\n1280x720\n' > "$T/drm/card0-eDP-1/modes"
printf 'disconnected' > "$T/drm/card0-HDMI-1/status"
[ "$(KO_SYSFS_DRM=$T/drm detect_screen)" = "1366x768" ] \
    && ok "detect prefers first connected DRM mode" \
    || bad "detect DRM wrong"
printf 'disconnected' > "$T/drm/card0-eDP-1/status"
# No connected DRM output here: xrandr (if reachable) or the 1080p fallback.
# Either way the result must be well-formed; the exact tier is env-specific.
case "$(KO_SYSFS_DRM=$T/drm detect_screen)" in
    ''|*[!0-9x]*) bad "detect fallback malformed" ;;
    *) ok "detect fallback well-formed" ;;
esac

# 13. seed_cells patches kitty+foot only; result still parses.
cp "$KO_ROOT/config.jsonc.example" "$T/seed.jsonc"
seed_cells "$T/seed.jsonc" 105 28
[ "$(grep -c '"width": 105' "$T/seed.jsonc")" -eq 2 ] \
    && [ "$(grep -c '"height": 28' "$T/seed.jsonc")" -eq 2 ] \
    && ok "seed writes both terminals" \
    || bad "seed missed a terminal section"
if python3 "$KO_ROOT/lib/jconfig.py" "$T/seed.jsonc" >/dev/null 2>&1; then
    ok "seeded config still parses"
else
    bad "seed broke config syntax"
fi

printf -- '---\npass=%s fail=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
