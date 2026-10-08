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

rm -f /tmp/ko-test-mpd.conf
printf -- '---\npass=%s fail=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
