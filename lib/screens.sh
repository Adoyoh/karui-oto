#!/bin/bash
# ============================================================================
# karui-oto · lib/screens.sh — screen detection + cell sizing for installs
# ----------------------------------------------------------------------------
# WHAT:
#   Fresh installs seed width/height cells sized to ~75% of the user's
#   screen, so the picker (and the compositor rules derived from the same
#   metrics in rules_px) lands big on 768p through 4K with no manual
#   tuning. Existing configs are NEVER touched (install.sh only seeds on
#   creation; setup preserves values).
#
# TIERS (first hit wins):
#   1. DRM sysfs: first connected output, first (preferred) mode. No deps.
#      KO_SYSFS_DRM overrides the base dir (tests).
#   2. xrandr primary (else first connected) mode (X11/XWayland sessions).
#   3. Fallback 1920x1080 (most common desktop; headless installs).
# ============================================================================

# detect_screen: print "WxH" (e.g. 1366x768). Always succeeds.
detect_screen() {
    local sysfs="${KO_SYSFS_DRM:-/sys/class/drm}" d st m
    for d in "$sysfs"/card*-*; do
        [ -f "$d/status" ] || continue
        st="$(cat "$d/status" 2>/dev/null)"
        [ "$st" = "connected" ] || continue
        m="$(head -n 1 "$d/modes" 2>/dev/null)"
        if [[ "$m" =~ ^([0-9]+)x([0-9]+)$ ]]; then
            printf '%sx%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
            return 0
        fi
    done
    if command -v xrandr >/dev/null 2>&1; then
        m="$(xrandr --current 2>/dev/null | grep -oE 'primary [0-9]+x[0-9]+' | head -n 1 | grep -oE '[0-9]+x[0-9]+')"
        if [[ "$m" =~ ^([0-9]+)x([0-9]+)$ ]]; then
            printf '%sx%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
            return 0
        fi
        m="$(xrandr --current 2>/dev/null | grep -E ' connected ' | grep -oE '[0-9]+x[0-9]+\+' | head -n 1 | tr -d '+')"
        if [[ "$m" =~ ^([0-9]+)x([0-9]+)$ ]]; then
            printf '%sx%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
            return 0
        fi
    fi
    printf '1920x1080'
}

# cells_for_screen <WxH> [font_size] [pad]: cols rows covering ~75% of the
# screen using the inverse of the rules_px cell metrics (advance ~0.6em,
# ~1.25em tall). Floors (40 cols, 10 rows): below that fzf is unusable,
# so tiny/odd readings clamp instead of producing garbage. Prints "c r".
cells_for_screen() {
    local sw="${1%x*}" sh="${1#*x}" fs="${2:-16}" pad="${3:-8}" c r
    c="$(awk -v s="$sw" -v f="$fs" -v p="$pad" 'BEGIN{ printf "%.0f", (0.75 * s - 2 * p) / (f * 0.6) }')"
    r="$(awk -v s="$sh" -v f="$fs" -v p="$pad" 'BEGIN{ printf "%.0f", (0.75 * s - 2 * p) / (f * 1.25) }')"
    [ "$c" -ge 40 ] || c=40
    [ "$r" -ge 10 ] || r=10
    printf '%s %s' "$c" "$r"
}

# seed_cells <config-file> <cols> <rows>: set width/height in the kitty and
# foot sections of a FRESH config.jsonc copy. Section-scoped sed ranges
# (the example format is fixed and owned here); anything else untouched.
seed_cells() {
    local file="$1" c="$2" r="$3"
    sed -i \
        -e '/"kitty": {/,/},/ s/"width": [0-9]*/"width": '"$c"'/' \
        -e '/"kitty": {/,/},/ s/"height": [0-9]*/"height": '"$r"'/' \
        -e '/"foot": {/,/},/ s/"width": [0-9]*/"width": '"$c"'/' \
        -e '/"foot": {/,/},/ s/"height": [0-9]*/"height": '"$r"'/' \
        "$file"
}
