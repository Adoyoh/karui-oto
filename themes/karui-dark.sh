# ============================================================================
# karui-oto · themes/karui-dark.sh
# ----------------------------------------------------------------------------
# WHAT:
#   The "original dark + coherent pink" palette: project-inherited Mocha
#   base with pink accent. Loaded by lib/common.sh per THEME=....
#
# WHERE IT FITS:
#   Defines FZF_COLOR (fzf --color string), C_* ANSI colors for awk
#   formatting and terminal bg/text for foot. lib/picker.sh consumes them.
#   Icons do NOT live here: they come from the config `icons` section
#   (see picker.sh). To tweak the palette, copy this file (new theme)
#   instead of editing it: upgrades won't clobber your changes.
#
# HOW TO EXTEND (new theme, e.g. themes/latte.sh):
#   1) Copy this file. 2) Change values (same names).
#   3) "theme": "latte" in config.jsonc. Nothing else: no code references
#      hardcoded colors outside here (finding one is a bug).
#
# NAMING:
#   FZF_* = fzf flags. C_* = ANSI escapes for awk (\033[38;2;R;G;Bm).
#   TERM_* = terminal bg/text (foot; kitty uses your global theme).
# ============================================================================

# --- fzf base (no `bg` key: transparent, inherits the terminal) --------------
FZF_COLOR="bg+:#313244,spinner:#f5e0dc,hl:#ea76cb,fg:#cdd6f4,header:#ea76cb,info:#bac2de,pointer:#ea76cb,marker:#f5c2e7,fg+:#cdd6f4,prompt:#ea76cb,hl+:#ea76cb,border:#ea76cb,scrollbar:#ea76cb"

# --- Songs list hierarchy (pink family on dark) ------------------------------
C_ARTIST='\033[38;2;235;160;172m'   # soft flamingo
C_ALBUM='\033[38;2;186;194;222m'    # cool lavender (contrast)
C_TRACK='\033[1;38;2;245;224;220m'  # bright rosewater + bold (track only)
C_SEP='\033[38;2;108;112;134m'      # dim separators
C_RESET='\033[0m'
C_SEP_TXT=' · '

# --- Terminal bg (used by foot; kitty uses your global theme) ----------------
TERM_BG="1e1e2e"   # Mocha base (foot: -o colors.background=, no #)
TERM_FG="cdd6f4"   # Mocha text
