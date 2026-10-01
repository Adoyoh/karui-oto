#!/bin/bash
# ============================================================================
# karui-oto · terminals/foot.sh — foot adapter
# ----------------------------------------------------------------------------
# WHAT:
#   Same as kitty.sh but in foot dialect (native Wayland, lightweight).
#   Same public term_open() with identical contract: modes never know
#   which terminal they run in.
#
# EQUIVALENCES (verified with foot 1.21 + niri):
#   --class=X            -> -a X               (app-id, compositor rules)
#   size                 -> -W WIDTHxHEIGHT (cells, knobs shared with
#                           kitty; physical size varies slightly by font)
#   window_padding 8     -> -o pad=8x8
#   font + size          -> -f "Fam:size=N"    (fontconfig format)
#   bg/text              -> -o colors.background/foreground (from config
#                           `color` or the theme; see T_BG/T_FG in term_open)
#   transparency         -> -o colors.alpha (TRANSPARENCY_FOOT). NOTE: foot
#                           has NO per-color alpha (RRGGBB without alpha
#                           channel); its global `alpha` fades EVEN THE TEXT
#                           and washes it out. kitty separates bg from text.
#                           Default 1.0 = solid: full text presence.
#   no title bar         -> -o csd.preferred=none (like kitty's
#                           hide_window_decorations; niri has no decoration
#                           manager and foot drew its own)
#   -e script            -> bare trailing script (its -e is compat, works
#                           the same, but flagless is more portable)
#
# OPTIONAL EXTRA: foot --server + footclient opens instant windows
# (faster than kitty for the on-demand philosophy). Off by default so no
# running server is required; see README (FAQ).
# ============================================================================

# See lib/terminals kitty.sh for the term_open() contract.
# Bg/text: config `color` (T_BG/T_FG) or the theme when empty.
# Transparency: colors.alpha = TRANSPARENCY_FOOT (1.0 = solid; lower
# washes even the text — foot limitation, see note above).
term_open() {
    local bg="${T_BG:-$TERM_BG}" fg="${T_FG:-$TERM_FG}"
    local args=(-a "$TERM_CLASS" -W "${WIDTH}x${HEIGHT}"
        -o "pad=${WIN_PAD}x${WIN_PAD}"
        -f "$FONT:size=$FONT_SIZE"
        -o "colors.background=$bg" -o "colors.foreground=$fg"
        -o "colors.alpha=$TRANSPARENCY_FOOT"
        -o csd.preferred=none)
    if [ "${KO_DRYRUN:-0}" = "1" ]; then
        printf 'foot'; printf ' %q' "${args[@]}" -- "$@"
        printf '\n'
        return 0
    fi
    # Redirections: see kitty.sh (without this the caller hangs).
    foot "${args[@]}" -- "$@" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null
}
