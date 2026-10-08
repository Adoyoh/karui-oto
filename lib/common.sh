#!/bin/bash
# ============================================================================
# karui-oto · lib/common.sh
# ----------------------------------------------------------------------------
# WHAT:
#   Shared foundations: JSONC config loading + validation, path resolution,
#   MPD helpers (wait, start, kill), deferred MPRIS and utils
#   (die/log/need_cmd).
#
# WHERE IT FITS:
#   bin/karui-oto and bin/karui-media import it with:
#       source "$KO_ROOT/lib/common.sh"
#   where KO_ROOT resolves itself (symlink-safe, e.g. ~/.local/bin).
#   Nothing here opens windows or touches the queue: groundwork only.
#   Interaction lives in lib/picker.sh and terminals/.
#
# HOW TO EXTEND (guide for humans and AIs):
#   - New config knob: 1) default in defaults() 2) validation in
#     validate() 3) document it in config.jsonc.example with the SAME
#     name, in the SAME relative order. Missing a step = knob doesn't exist.
#   - New MPD helper: small function returning 0/1 that NEVER exits
#     (the caller decides). lowercase_with_underscores names.
#   - Error convention: die() for fatals (exit 1 + stderr message),
#     return 1 for recoverables inside functions.
#
# CONFIG FLOW (important — strict order, do not reorder):
#   defaults() -> [config.jsonc if present: parser eval] -> theme ->
#   derived (contrast, HIDE_RE) -> validate().
#   KARUI_OTO_CONFIG env var allows override (tests). An existing user
#   config is NEVER overwritten (see install.sh).
# ============================================================================
set -u
# NOTE: no `set -e` on purpose. mpc/fzf fail in normal cases (empty queue,
# Esc in fzf) and each caller decides what to do.

# --- Project root (resolves symlinks: works installed or in repo) --------
if [ -z "${KO_ROOT:-}" ]; then
    _sp_src="${BASH_SOURCE[0]}"
    while [ -L "$_sp_src" ]; do
        _sp_dir="$(cd -P -- "$(dirname -- "$_sp_src")" >/dev/null 2>&1 && pwd -P)"
        _sp_src="$(readlink "$_sp_src")"
        case "$_sp_src" in
            /*) : ;; # absoluto: queda igual
            *) _sp_src="$_sp_dir/$_sp_src" ;;
        esac
    done
    # lib/common.sh -> root = lib/..
    KO_ROOT="$(cd -P -- "$(dirname -- "$_sp_src")/.." >/dev/null 2>&1 && pwd -P)"
    unset _sp_src _sp_dir
fi

# --- Defaults (same order as config.jsonc.example) ---------------------------
# default_music_dir: first existing candidate so English and Spanish
# home folders both work out of the box (Música/Music/music/Musica),
# preferring the freedesktop XDG music dir when xdg-user-dirs knows it.
default_music_dir() {
    local d
    if command -v xdg-user-dir >/dev/null 2>&1; then
        d="$(xdg-user-dir MUSIC 2>/dev/null)"
        # xdg-user-dir prints $HOME itself when MUSIC is disabled: ignore it.
        if [ -n "$d" ] && [ "$d" != "$HOME" ] && [ "$d" != "$HOME/" ] && [ -d "$d" ]; then
            printf '%s' "$d"; return 0
        fi
    fi
    for d in "$HOME/Música" "$HOME/Music" "$HOME/music" "$HOME/Musica"; do
        if [ -d "$d" ]; then printf '%s' "$d"; return 0; fi
    done
    printf '%s' "$HOME/Música"
}

defaults() {
    MUSIC_DIR="$(default_music_dir)"  # jsonc key: path
    MPD_CONF="$HOME/.config/mpd/mpd.conf"  # key: mpd_conf
    TERMINAL="kitty"              # kitty | foot (see terminals/)
    TERM_CLASS="buscador_mpd"     # app-id: matched by compositor rules
    # Per-terminal sections (each lives in "kitty"{...} / "foot"{...}).
    # Same shape, independent values: each terminal to its own taste.
    KITTY_FONT="Liberation Mono"  # fontconfig family (verified)
    KITTY_FONT_SIZE="16"          # points
    KITTY_WIDTH="120"             # cells: drives the compositor rule size
    KITTY_HEIGHT="30"             # (rules_px: ~1168x616 at 16pt, big pickup)
    KITTY_COLOR=""                # "" = your kitty global theme; "#rrggbb" = bg + auto-contrast text
    KITTY_TRANSPARENCY="0.85"    # 0.00–1.00, background ONLY
    FOOT_FONT="Liberation Mono"
    FOOT_FONT_SIZE="16"
    FOOT_WIDTH="124"              # cells: drives the compositor rule size
    FOOT_HEIGHT="34"              # (rules_px: ~1206x696 at 16pt, big pickup)
    FOOT_COLOR=""                 # "" = theme; "#rrggbb" + auto contrast
    FOOT_TRANSPARENCY="0.85"     # 0.00–1.00, WHOLE window (foot has no
                                  # per-color alpha: lower washes the text)
    WIN_PAD="8"                   # inner padding (advanced; no jsonc knob)
    THEME="karui-dark"            # file in themes/<name>.sh
    ICONS_SEARCH=$'\U0000F002'  # nerd magnifier (empty also works)
    ICONS_ARROW="▶"             # current-line pointer
    ICONS_MARKER="✓"
    ICONS_ALBUM="♪"
    ICONS_FOLDER=""
    # Per-element color overrides ("" = inherit the theme). Applied over
    # C_* and FZF_COLOR after the theme loads (see apply_font_colors).
    FC_ARTIST="";       FC_ALBUM="";        FC_TRACK=""
    FC_SEPARATOR="";    FC_HIGHLIGHT="";    FC_HIGHLIGHT_SELECTED=""
    FC_PROMPT="";       FC_POINTER="";      FC_MARKER=""
    FC_HEADER="";       FC_INFO="";         FC_BORDER=""
    FC_SCROLLBAR="";    FC_GUTTER="";       FC_BORDER_LABEL=""
    FC_LIST_LABEL=""
    SHUFFLE="true"              # true: random on + shuffle. false: in order
    REPEAT="true"                # true: repeat on
    MPRIS="true"                  # true: start mpDris2 deferred after picking
    MIN_TRACKS="1"                # artists mode: hide artists with fewer
                                  # tracks (1 = show all, 2 hides one-track guests)
    HIDE=$'^\.\x1f^Various Artists$'  # grep -vE regexes, \x1f-separated
    # Shortcuts section (all empty = unassigned; fill to generate binds with
    # `karui-oto binds`). Canonical form: Mod+O, Mod+Shift+P.
    SHORTCUTS_SONGS=""
    SHORTCUTS_ARTISTS=""
    SHORTCUTS_ALBUMS=""
    SHORTCUTS_FOLDERS=""
    SHORTCUTS_KILL=""
    # Per-compositor overrides (empty section parts). A compositor inherits
    # the global SHORTCUTS_* unless its _PRESENT flag is set (jconfig sets
    # it when the section exists, even empty: empty mode = unassigned there).
    SHORTCUTS_NIRI_SONGS="";      SHORTCUTS_NIRI_ARTISTS=""
    SHORTCUTS_NIRI_ALBUMS="";     SHORTCUTS_NIRI_FOLDERS=""
    SHORTCUTS_NIRI_KILL="";       SHORTCUTS_NIRI_PRESENT=""
    SHORTCUTS_HYPRLAND_SONGS="";  SHORTCUTS_HYPRLAND_ARTISTS=""
    SHORTCUTS_HYPRLAND_ALBUMS=""; SHORTCUTS_HYPRLAND_FOLDERS=""
    SHORTCUTS_HYPRLAND_KILL="";   SHORTCUTS_HYPRLAND_PRESENT=""
    # Per-mode overrides (jsonc key: modes.<mode>.<knob>). Empty = inherit
    # the global SHUFFLE/REPEAT/MPRIS above; true/false wins for that mode.
    MODES_SONGS_SHUFFLE="";   MODES_SONGS_REPEAT="";   MODES_SONGS_MPRIS=""
    MODES_ARTISTS_SHUFFLE=""; MODES_ARTISTS_REPEAT=""; MODES_ARTISTS_MPRIS=""
    MODES_ALBUMS_SHUFFLE="";  MODES_ALBUMS_REPEAT="";  MODES_ALBUMS_MPRIS=""
    MODES_FOLDERS_SHUFFLE=""; MODES_FOLDERS_REPEAT=""; MODES_FOLDERS_MPRIS=""
    # Logo section (jsonc key: logo[]). Indexed LOGO_<i>_* vars arrive via
    # jconfig (LOGO_COUNT items); empty section = no logo anywhere.
    LOGO_COUNT="0"
    KARUI_OTO_CONFIG="${KARUI_OTO_CONFIG:-$HOME/.config/karui-oto/config.jsonc}"
}

# --- Loading: defaults < config.jsonc (the file WINS) -----------------------
load_config() {
    defaults
    if [ -f "$KARUI_OTO_CONFIG" ]; then
        need_cmd python3
        local _out _rc
        _out="$(python3 "$KO_ROOT/lib/jconfig.py" "$KARUI_OTO_CONFIG" 2>/tmp/ko_jconfig.err)"
        _rc=$?
        if [ "$_rc" -eq 1 ]; then
            cat /tmp/ko_jconfig.err >&2
            die "invalid config: $KARUI_OTO_CONFIG"
        fi
        rm -f /tmp/ko_jconfig.err
        [ "$_rc" -eq 0 ] && eval "$_out"
        # exit 2 = unreadable file: carry on with defaults (unreachable here
        # since -f already confirmed it, but kept for robustness).
        unset _out _rc
    fi
    # Per-invocation override WITHOUT touching the file: e.g. a test alias
    # with another terminal (KARUI_OTO_TERMINAL=foot). Validated as if it came
    # from the jsonc (validate() can't tell the origin).
    [ -n "${KARUI_OTO_TERMINAL:-}" ] && TERMINAL="$KARUI_OTO_TERMINAL"
    # ~ never expands alone inside JSON: expand once, here.
    expand_tilde MUSIC_DIR
    expand_tilde MPD_CONF
    seleccionar_terminal
    # Theme provides the palette (FZF_COLOR, C_*). Goes AFTER so user
    # config can override theme colors.
    if [ -f "$KO_ROOT/themes/$THEME.sh" ]; then
        source "$KO_ROOT/themes/$THEME.sh"
    else
        die "Theme not found: themes/$THEME.sh (theme=$THEME)"
    fi
    derivados
    validate
}

# Copies the active section (kitty/foot) into the working vars used by the
# adapters (FONT, WIDTH, COLOR...). So terminals/kitty.sh never knows foot
# exists and vice versa. With an invalid TERMINAL, kitty is used so that
# validate() fails later with ITS clear message (not a cryptic one here).
seleccionar_terminal() {
    local p="KITTY" v ref
    [ "$TERMINAL" = "foot" ] && p="FOOT"
    for v in FONT FONT_SIZE WIDTH HEIGHT COLOR; do
        ref="${p}_$v"
        printf -v "$v" '%s' "${!ref}"
    done
    TRANSPARENCY_KITTY="$KITTY_TRANSPARENCY"
    TRANSPARENCY_FOOT="$FOOT_TRANSPARENCY"
}

# apply_mode_overrides <mode>: resolve effective SHUFFLE/REPEAT/MPRIS for
# one picker run. Per-mode modes.<mode>.* wins when non-empty, else the
# global from setup stays. Called by run_pick() before any queue work so
# queue_*, apply_modes and launch_mpris all see the effective values.
apply_mode_overrides() {
    local _mm="${1^^}" _k _var _val
    for _k in SHUFFLE REPEAT MPRIS; do
        _var="MODES_${_mm}_${_k}"
        _val="${!_var:-}"
        [ -n "$_val" ] && printf -v "$_k" '%s' "$_val"
    done
}

# fzf_color_set <key> <hex>: point one fzf --color entry at a new color.
# FZF_COLOR is a flat "k:v,k:v" string from the theme; the key is replaced
# in place (or appended when the theme lacks it). Values always carry #
# (bare rrggbb from the config gets it prepended).
fzf_color_set() {
    local k="$1" v="$2" IFS=',' p out=""
    case "$v" in \#*) : ;; *) v="#$v" ;; esac
    for p in $FZF_COLOR; do
        case "$p" in "$k:"*) continue ;; *) out="${out:+$out,}$p" ;; esac
    done
    FZF_COLOR="${out:+$out,}$k:$v"
}

# apply_font_colors: font-colors{} overrides after the theme loaded.
# Text elements rewrite C_* (ANSI, via ansi_fg); fzf chrome rewrites
# FZF_COLOR entries. Empty = inherit theme (nothing to do). Precedence:
# font-colors > theme. Called at the end of derivados(), before validate().
apply_font_colors() {
    [ -n "${FC_ARTIST:-}" ]    && C_ARTIST="$(ansi_fg "$FC_ARTIST")"
    [ -n "${FC_ALBUM:-}" ]     && C_ALBUM="$(ansi_fg "$FC_ALBUM")"
    [ -n "${FC_TRACK:-}" ]     && C_TRACK="$(ansi_fg "$FC_TRACK")"
    [ -n "${FC_SEPARATOR:-}" ] && C_SEP="$(ansi_fg "$FC_SEPARATOR")"
    [ -n "${FC_HIGHLIGHT:-}" ]          && fzf_color_set "hl" "$FC_HIGHLIGHT"
    [ -n "${FC_HIGHLIGHT_SELECTED:-}" ] && fzf_color_set "hl+" "$FC_HIGHLIGHT_SELECTED"
    [ -n "${FC_PROMPT:-}" ]  && fzf_color_set "prompt" "$FC_PROMPT"
    [ -n "${FC_POINTER:-}" ] && fzf_color_set "pointer" "$FC_POINTER"
    [ -n "${FC_MARKER:-}" ]  && fzf_color_set "marker" "$FC_MARKER"
    [ -n "${FC_HEADER:-}" ]  && fzf_color_set "header" "$FC_HEADER"
    [ -n "${FC_INFO:-}" ]    && fzf_color_set "info" "$FC_INFO"
    [ -n "${FC_BORDER:-}" ]  && fzf_color_set "border" "$FC_BORDER"
    [ -n "${FC_SCROLLBAR:-}" ]     && fzf_color_set "scrollbar" "$FC_SCROLLBAR"
    [ -n "${FC_GUTTER:-}" ]        && fzf_color_set "gutter" "$FC_GUTTER"
    [ -n "${FC_BORDER_LABEL:-}" ]  && fzf_color_set "border-label" "$FC_BORDER_LABEL"
    [ -n "${FC_LIST_LABEL:-}" ]    && fzf_color_set "list-label" "$FC_LIST_LABEL"
    return 0
}

# --- Derivados: HIDE_RE, contraste automático ----------------------------------
derivados() {
    # hide[] (\x1f) -> alternancia grep -vE. Vacío = sin filtro.
    if [ -z "${HIDE//[$'\x1f']/}" ]; then
        HIDE_RE=""
    else
        HIDE_RE="${HIDE//$'\x1f'/|}"
    fi
    # color "#rrggbb"/"rrggbb" -> T_BG (no #) + T_FG by luminance
    # (light bg -> dark text 4c4f69; dark -> light text cdd6f4).
    # Empty = each terminal uses its default (kitty: global theme; foot: theme).
    T_BG=""; T_FG=""
    if [ -n "$COLOR" ]; then
        local hex="${COLOR#\#}"  # validated: #rrggbb or rrggbb
        local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
        local lum=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
        T_BG="$hex"
        if [ "$lum" -ge 128 ]; then T_FG="4c4f69"; else T_FG="cdd6f4"; fi
    fi
    derivados_logo
    apply_font_colors
}

# ansi_fg <hex>: print the \033[38;2;R;G;Bm escape for a #rrggbb color.
ansi_fg() {
    local hex="${1#\#}"
    printf '\033[38;2;%d;%d;%dm' "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

# logo_tinted <abspath>: print the tinted copy path for the current logo
# image (globals: _LOGO_TINT color, _LOGO_ALPHA informational only — alpha
# stays native via window_logo_alpha, only RGB is replaced). Cached under
# ~/.cache/karui-oto/ keyed by path+mtime+alpha+color, so steady-state picks
# pay one stat+sha (~ms). Without PIL: warn once, use the original.
logo_tinted() {
    local src="$1" cache key mtime
    mtime="$(stat -c %Y "$src" 2>/dev/null)"
    key="$(printf '%s|%s|%s|%s' "$src" "$mtime" "$_LOGO_ALPHA" "$_LOGO_TINT" | sha256sum 2>/dev/null | cut -d' ' -f1)"
    [ -n "$key" ] || { printf '%s' "$src"; return 0; }
    cache="$HOME/.cache/karui-oto/logo-$key.png"
    if [ -f "$cache" ]; then printf '%s' "$cache"; return 0; fi
    if [ "${_LOGO_PIL_OK:-unset}" = "unset" ]; then
        if python3 -c "import PIL.Image" >/dev/null 2>&1; then _LOGO_PIL_OK=1;
        else _LOGO_PIL_OK=0; fi
    fi
    if [ "$_LOGO_PIL_OK" = "1" ]; then
        mkdir -p "$(dirname "$cache")"
        if python3 - "$src" "$_LOGO_TINT" "$cache" <<'EOF' >/dev/null 2>&1
import sys
from PIL import Image
src, tint, dst = sys.argv[1], sys.argv[2].lstrip('#'), sys.argv[3]
img = Image.open(src).convert('RGBA')
r, g, b = int(tint[0:2], 16), int(tint[2:4], 16), int(tint[4:6], 16)
solid = Image.new('RGBA', img.size, (r, g, b, 255))
a = img.getchannel('A')
out = Image.merge('RGBA', solid.split()[:3] + (a,))
out.save(dst)
EOF
        then printf '%s' "$cache"; return 0; fi
    fi
    printf 'karui-oto: warning: logo tint needs python3-pil (using original image)\n' >&2
    printf '%s' "$src"
}

# derivados_logo: build LOGO_HEADER (symbols line for fzf --header) and
# KITTY_LOGO_OPTS (-o window_logo_* for the kitty adapter; foot ignores).
# Symbols are unlimited and work everywhere; at most ONE image (kitty shows
# a single window logo — validate() rejects more). Empty logo[] = both empty.
derivados_logo() {
    LOGO_HEADER=""; KITTY_LOGO_OPTS=(); LOGO_IMAGE_COUNT=0
    local n="${LOGO_COUNT:-0}" i type
    local left_s="" center_s="" right_s=""
    local img_path="" img_alpha="1.0" img_size="0" img_pos="bottom-right" img_tint=""
    for ((i = 0; i < n; i++)); do
        if [ -n "$(eval "printf '%s' \"\${LOGO_${i}_SYMBOL:-}\"")" ]; then
            type="symbol"
        else
            type="image"
        fi
        if [ "$type" = "symbol" ]; then
            local sym col size pos esc attr seg
            sym="$(eval "printf '%s' \"\${LOGO_${i}_SYMBOL:-}\"")"
            col="$(eval "printf '%s' \"\${LOGO_${i}_COLOR:-}\"")"
            size="$(eval "printf '%s' \"\${LOGO_${i}_SIZE:-}\"")"
            pos="$(eval "printf '%s' \"\${LOGO_${i}_POSITION:-}\"")"
            [ -n "$col" ] || col="#ea76cb"
            # Guard: validate() dies right after with the clean message;
            # derivados must never crash on it first (16# arithmetic).
            [[ "$col" =~ ^#?[0-9a-fA-F]{6}$ ]] || col="#ea76cb"
            case "$size" in ""|normal) attr="" ;; large) attr='\033[1m' ;; small) attr='\033[2m' ;; *) attr="" ;; esac
            esc="$(ansi_fg "$col")"
            seg="${esc}${attr}${sym}\033[0m"
            case "$pos" in
                ""|left) left_s="${left_s:+$left_s  }$seg" ;;
                center) center_s="${center_s:+$center_s  }$seg" ;;
                right) right_s="${right_s:+$right_s  }$seg" ;;
                *) left_s="${left_s:+$left_s  }$seg" ;;
            esac
        else
            LOGO_IMAGE_COUNT=$((LOGO_IMAGE_COUNT + 1))
            [ "$LOGO_IMAGE_COUNT" -eq 1 ] || continue
            img_path="$(eval "printf '%s' \"\${LOGO_${i}_IMAGE:-}\"")"
            case "$img_path" in "~"/*) img_path="$HOME/${img_path#\~/}" ;; "~") img_path="$HOME" ;; esac
            img_alpha="$(eval "printf '%s' \"\${LOGO_${i}_TRANSPARENCY:-}\"")"
            img_size="$(eval "printf '%s' \"\${LOGO_${i}_SIZE:-}\"")"
            img_pos="$(eval "printf '%s' \"\${LOGO_${i}_POSITION:-}\"")"
            img_tint="$(eval "printf '%s' \"\${LOGO_${i}_COLOR:-}\"")"
            [ -n "$img_alpha" ] || img_alpha="1.0"
            [ -n "$img_size" ] || img_size="0"
            [ -n "$img_pos" ] || img_pos="bottom-right"
        fi
    done
    # One header line: left flushed, right flushed, center centered on WIDTH.
    # Visible length strips ANSI (emoji counts ~1 cell: documented approx).
    if [ -n "$left_s$center_s$right_s" ]; then
        local w="${WIDTH:-95}" l_len c_len r_len pad
        l_len="$(printf '%s' "$left_s" | sed 's/\x1b\[[0-9;]*m//g' | wc -m)"
        c_len="$(printf '%s' "$center_s" | sed 's/\x1b\[[0-9;]*m//g' | wc -m)"
        r_len="$(printf '%s' "$right_s" | sed 's/\x1b\[[0-9;]*m//g' | wc -m)"
        LOGO_HEADER="$left_s"
        if [ -n "$center_s" ]; then
            pad=$(( (w - c_len) / 2 - l_len ))
            [ "$pad" -lt 1 ] && pad=1
            LOGO_HEADER="$LOGO_HEADER$(printf '%*s' "$pad" '')$center_s"
            l_len=$(( l_len + pad + c_len ))
        fi
        if [ -n "$right_s" ]; then
            pad=$(( w - l_len - r_len ))
            [ "$pad" -lt 1 ] && pad=1
            LOGO_HEADER="$LOGO_HEADER$(printf '%*s' "$pad" '')$right_s"
        fi
    fi
    # Kitty window logo (single image). Tint preprocesses RGB only; alpha
    # stays native via window_logo_alpha (validated range, see validate()),
    # mapped through perceptual_alpha() so low values bite harder.
    if [ "$LOGO_IMAGE_COUNT" -ge 1 ] && [ -f "$img_path" ]; then
        local final="$img_path"
        if [[ "$img_tint" =~ ^#?[0-9a-fA-F]{6}$ ]]; then
            _LOGO_ALPHA="$img_alpha" _LOGO_TINT="$img_tint"
            final="$(logo_tinted "$img_path")"
        fi
        KITTY_LOGO_OPTS=(-o "window_logo_path=$final"
            -o "window_logo_alpha=$(perceptual_alpha "$img_alpha")"
            -o "window_logo_scale=$img_size"
            -o "window_logo_position=$img_pos")
    fi
}

# perceptual_alpha <0.00-1.00>: cube the input for kitty window logos.
# Brightness perception is nonlinear: even a squared curve left 0.10
# clearly visible, forcing users near zero for background images. Cubing
# maps the knob to perceived strength (0.10 -> 0.00, 0.40 -> 0.06,
# 0.60 -> 0.22) while keeping both ends exact (0 -> 0.00, 1 -> 1.00).
# Validation still applies to the INPUT range, so no other code changes.
perceptual_alpha() {
    awk -v v="${1:-1.0}" 'BEGIN{ if (v < 0) v = 0; if (v > 1) v = 1; printf "%.2f", v * v * v }'
}

# --- Strict validation: fail fast with a clear message -----------------------
KNOWN_KEYS="path mpd_conf terminal term_class kitty foot theme icons shuffle repeat mpris min_tracks hide shortcuts shortcuts_niri shortcuts_hyprland font-colors modes logo"
# shortcut_for <mode-lower> <comp>: effective combo for the compositor.
# Own section present -> its value (empty = unassigned there); otherwise
# the global shortcuts{} value. Unknown comps resolve to "" (never die
# here: callers decide).
shortcut_for() {
    local m="${1^^}" c pvar var
    case "${2,,}" in
        niri) c="NIRI" ;;
        hyprland) c="HYPRLAND" ;;
        *) printf '%s' ""; return 0 ;;
    esac
    pvar="SHORTCUTS_${c}_PRESENT"; var="SHORTCUTS_${c}_${m}"
    if [ "${!pvar:-}" = "true" ]; then printf '%s' "${!var:-}";
    else var="SHORTCUTS_${m}"; printf '%s' "${!var:-}"; fi
}
# combo_canonical_ok <combo>: 0 if canonical shortcut form. Single source
# of truth: setup.sh combo_ok() delegates here, validate() below enforces.
combo_canonical_ok() {
    local re_combo='^(Mod|Shift|Ctrl|Alt)(\+(Mod|Shift|Ctrl|Alt))*\+([A-Z0-9]|F[0-9]{1,2}|XF86[A-Za-z]+|space|Tab|Escape|Return|BackSpace|Delete|Insert|Home|End|Page_Up|Page_Down)$'
    local re_bare='^(F[0-9]{1,2}|XF86[A-Za-z]+)$'
    [[ "$1" =~ $re_combo ]] || [[ "$1" =~ $re_bare ]]
}
# font_present_cached: 0 if $FONT resolves via fontconfig. Caches positive
# hits for 24h under ~/.cache/karui-oto (fonts rarely change; saves ~26ms
# per picker launch). Misses are never cached (always re-warned).
# KO_NO_FONT_CACHE=1 bypasses the cache (deterministic tests).
font_present_cached() {
    if [ -n "${KO_NO_FONT_CACHE:-}" ]; then
        fc-list : family 2>/dev/null | grep -qi "^${FONT}$"
        return "$?"
    fi
    local cache="$HOME/.cache/karui-oto/fontcheck"
    if [ -f "$cache" ] && [ "$(cat "$cache" 2>/dev/null)" = "$FONT" ] \
        && [ -n "$(find "$cache" -mtime -1 2>/dev/null)" ]; then
        return 0
    fi
    if fc-list : family 2>/dev/null | grep -qi "^${FONT}$"; then
        mkdir -p "$(dirname "$cache")"
        printf '%s' "$FONT" > "$cache"
        return 0
    fi
    return 1
}
validate() {
    # Unknown keys = warning (likely typo), not fatal.
    local k
    for k in ${KO_KEYS:-}; do
        case " $KNOWN_KEYS " in
            *" $k "*) : ;;
            *) printf 'karui-oto: warning: unknown config key: %s\n' "$k" >&2 ;;
        esac
    done
    case "$TERMINAL" in kitty|foot) : ;;
        *) die "terminal='$TERMINAL' invalid (valid: kitty foot)" ;;
    esac
    # app-id anchor: compositor rules and foot -a match on this. Spaces or
    # odd characters break matching silently, so the charset is restricted.
    [[ "${TERM_CLASS:-}" =~ ^[A-Za-z0-9_.-]+$ ]] \
        || die "term_class='${TERM_CLASS:-}' invalid (use letters, digits, _ . - only)"
    for b in SHUFFLE REPEAT MPRIS; do
        case "${!b}" in true|false) : ;;
            *) die "$b='${!b}' invalid (valid: true false)" ;;
        esac
    done
    # Per-mode overrides: empty = inherit (skipped), else strict booleans.
    local _m _k _var _val
    for _m in SONGS ARTISTS ALBUMS FOLDERS; do
        for _k in SHUFFLE REPEAT MPRIS; do
            _var="MODES_${_m}_${_k}"
            _val="${!_var:-}"
            case "$_val" in ""|true|false) : ;;
                *) die "modes.${_m,,}.${_k,,}='$_val' invalid (valid: true false, empty = inherit global)" ;;
            esac
        done
    done
    [[ "${MIN_TRACKS:-1}" =~ ^[0-9]+$ ]] && [ "${MIN_TRACKS:-1}" -ge 1 ] \
        || die "min_tracks='${MIN_TRACKS:-}' invalid (integer >= 1)"
    # hide[]: every pattern must compile. An invalid regex would blow up the
    # list-building grep at runtime with no clue which item broke it.
    local _hitem _hidx=0 _harr
    local IFS=$'\x1f'
    read -ra _harr <<<"${HIDE:-}"
    for _hitem in "${_harr[@]}"; do
        _hidx=$((_hidx + 1))
        [ -n "$_hitem" ] || continue
        printf '' | grep -vE "$_hitem" >/dev/null 2>&1
        [ "$?" -le 1 ] || die "hide item #$_hidx invalid regex: $_hitem"
    done
    IFS=$' \t\n'
    # Logo[] (kitty-only images, universal symbols): strict per item.
    # Symbols: non-empty text; color empty (= theme pink) or #rrggbb;
    # size empty/normal/small/large; position empty/left/center/right.
    # Images: existing file; transparency empty (1.0) or 0.00–1.00; size
    # empty (native) or 0–100; position empty (bottom-right) or the 9-point
    # vocabulary; color empty (no tint) or #rrggbb (needs python3-pil,
    # else warn + original). At most ONE image (kitty shows a single logo).
    local _li _lv _nimg=0
    [[ "${LOGO_COUNT:-0}" =~ ^[0-9]+$ ]] \
        || die "logo has ${LOGO_COUNT:-?} items (internal: LOGO_COUNT must be an integer)"
    for ((_li = 0; _li < LOGO_COUNT; _li++)); do
        if [ -n "$(eval "printf '%s' \"\${LOGO_${_li}_SYMBOL:-}\"")" ]; then
            _lv="$(eval "printf '%s' \"\${LOGO_${_li}_COLOR:-}\"")"
            [ -z "$_lv" ] || [[ "$_lv" =~ ^#?[0-9a-fA-F]{6}$ ]] \
                || die "logo[$_li].color='$_lv' invalid (format: #rrggbb)"
            _lv="$(eval "printf '%s' \"\${LOGO_${_li}_SIZE:-}\"")"
            case "$_lv" in ""|normal|small|large) : ;;
                *) die "logo[$_li].size='$_lv' invalid (valid: small normal large)" ;; esac
            _lv="$(eval "printf '%s' \"\${LOGO_${_li}_POSITION:-}\"")"
            case "$_lv" in ""|left|center|right) : ;;
                *) die "logo[$_li].position='$_lv' invalid (valid: left center right)" ;; esac
        else
            _nimg=$((_nimg + 1))
            [ "$_nimg" -le 1 ] \
                || die "logo[$_li]: only one image logo is supported (kitty shows a single window logo)"
            _lv="$(eval "printf '%s' \"\${LOGO_${_li}_IMAGE:-}\"")"
            [ -n "$_lv" ] || die "logo[$_li].image is empty (give a file path)"
            local _lp="$_lv"
            case "$_lp" in "~"/*) _lp="$HOME/${_lv#\~/}" ;; "~") _lp="$HOME" ;; esac
            [ -f "$_lp" ] || die "logo[$_li].image not found: $_lv"
            _lv="$(eval "printf '%s' \"\${LOGO_${_li}_TRANSPARENCY:-}\"")"
            if [ -n "$_lv" ]; then
                [[ "$_lv" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v v="$_lv" 'BEGIN{ exit !(v >= 0 && v <= 1) }' \
                    || die "logo[$_li].transparency='$_lv' invalid (number 0.00–1.00)"
            fi
            _lv="$(eval "printf '%s' \"\${LOGO_${_li}_SIZE:-}\"")"
            if [ -n "$_lv" ]; then
                [[ "$_lv" =~ ^[0-9]+$ ]] && [ "$_lv" -ge 0 ] && [ "$_lv" -le 100 ] \
                    || die "logo[$_li].size='$_lv' invalid (integer 0–100)"
            fi
            _lv="$(eval "printf '%s' \"\${LOGO_${_li}_POSITION:-}\"")"
            case "$_lv" in ""|top-left|top|top-right|left|center|right|bottom-left|bottom|bottom-right) : ;;
                *) die "logo[$_li].position='$_lv' invalid (valid: top-left top top-right left center right bottom-left bottom bottom-right)" ;; esac
            _lv="$(eval "printf '%s' \"\${LOGO_${_li}_COLOR:-}\"")"
            [ -z "$_lv" ] || [[ "$_lv" =~ ^#?[0-9a-fA-F]{6}$ ]] \
                || die "logo[$_li].color='$_lv' invalid (format: #rrggbb)"
        fi
    done
    # foot shows symbols but never images (no window-image option there).
    if [ "$TERMINAL" = "foot" ] && [ "$_nimg" -ge 1 ]; then
        printf 'karui-oto: warning: logo image ignored on foot (kitty only); symbols still show\n' >&2
    fi
    # Both sections are validated (even though only one opens): typos in
    # the inactive one are caught too. P=KITTY|FOOT prefix.
    local P var re_num='^[0-9]+(\.[0-9]+)?$' re_int='^[0-9]+$'
    for P in KITTY FOOT; do
        var="${P}_TRANSPARENCY"
        [[ "${!var}" =~ $re_num ]] || die "$var='${!var}' invalid (number 0.00–1.00)"
        awk -v v="${!var}" 'BEGIN{ exit !(v >= 0 && v <= 1) }' \
            || die "$var='${!var}' out of range (0.00–1.00)"
        for s in WIDTH HEIGHT FONT_SIZE; do
            var="${P}_$s"
            [[ "${!var}" =~ $re_int ]] && [ "${!var}" -ge 1 ] \
                || die "$var='${!var}' invalid (integer >= 1)"
        done
        var="${P}_COLOR"
        if [ -n "${!var}" ]; then
            [[ "${!var}" =~ ^#?[0-9a-fA-F]{6}$ ]] \
                || die "$var='${!var}' invalid (format: #rrggbb)"
        fi
    done
    # font-colors{}: empty inherits the theme, otherwise strict #rrggbb.
    local _fc _fck
    for _fc in FC_ARTIST FC_ALBUM FC_TRACK FC_SEPARATOR FC_HIGHLIGHT \
               FC_HIGHLIGHT_SELECTED FC_PROMPT FC_POINTER FC_MARKER \
               FC_HEADER FC_INFO FC_BORDER FC_SCROLLBAR FC_GUTTER \
               FC_BORDER_LABEL FC_LIST_LABEL; do
        # Display name back to config spelling (only these two use dashes).
        case "$_fc" in
            FC_BORDER_LABEL) _fck="border-label" ;;
            FC_LIST_LABEL) _fck="list-label" ;;
            *) _fck="${_fc#FC_}"; _fck="${_fck,,}" ;;
        esac
        [ -z "${!_fc}" ] || [[ "${!_fc}" =~ ^#?[0-9a-fA-F]{6}$ ]] \
            || die "font-colors.${_fck}='${!_fc}' invalid (format: #rrggbb, empty = inherit theme)"
    done
    # Shortcuts: empty = unassigned (skipped by `binds`); otherwise strict
    # CANONICAL form (capital M, translators depend on it): Mod+O,
    # Mod+Shift+P. Bare keys only for F-keys/XF86 (a bare "C" would hijack
    # typing, so it is rejected on purpose). Lowercase "mod+c" is rejected
    # too: sway/i3 need the $mod variable and niri matching gets ambiguous.
    local sc
    for sc in SONGS ARTISTS ALBUMS FOLDERS KILL; do
        var="SHORTCUTS_$sc"
        [ -n "${!var}" ] || continue
        combo_canonical_ok "${!var}" \
            || die "shortcuts.${sc,,}='${!var}' invalid (canonical: Mod+O, Mod+Shift+P, XF86AudioPlay)"
    done
    # Per-compositor overrides use the same canonical form (empty inherits
    # nothing here: an existing section owns every mode, empty = unassigned).
    local _pc _pv
    for _pc in NIRI HYPRLAND; do
        _pv="SHORTCUTS_${_pc}_PRESENT"
        [ "${!_pv:-}" = "true" ] || continue
        for sc in SONGS ARTISTS ALBUMS FOLDERS KILL; do
            var="SHORTCUTS_${_pc}_${sc}"
            [ -n "${!var}" ] || continue
            combo_canonical_ok "${!var}" \
                || die "shortcuts_${_pc,,}.${sc,,}='${!var}' invalid (canonical: Mod+O, Mod+Shift+P, XF86AudioPlay)"
        done
    done
    # Font: active one only (the other may not exist if never used).
    font_present_cached \
        || printf 'karui-oto: warning: font "%s" not found (will fall back)\n' "$FONT" >&2
    [ -d "$MUSIC_DIR" ] || die "path does not exist: $MUSIC_DIR"
    [ -f "$MPD_CONF" ] || die "mpd_conf does not exist: $MPD_CONF"
    # -f not -x: .sh files are sourced, not executed (+x belongs to
    # bin/* and install.sh only; see verification in install.sh).
    [ -f "$KO_ROOT/terminals/$TERMINAL.sh" ] \
        || die "Missing terminal adapter: terminals/$TERMINAL.sh"
}

# --- Utils -------------------------------------------------------------------
die()  { printf 'karui-oto: error: %s\n' "$*" >&2; exit 1; }
log()  { [ "${KO_DEBUG:-0}" = "1" ] && printf 'karui-oto: %s\n' "$*" >&2; :; }

# expand_tilde <var>: expand leading ~ in place (bash never expands it
# inside variables or JSON strings; the load path does it too, but
# interactive checks like -d need it BEFORE validating).
expand_tilde() {
    local _et="$1" _v
    _v="${!_et:-}"
    case "$_v" in
        "~"/*) printf -v "$_et" '%s' "$HOME/${_v#\~/}" ;;
        "~")   printf -v "$_et" '%s' "$HOME" ;;
    esac
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

# --- MPD ---------------------------------------------------------------------
mpd_vivo() { pgrep -x mpd >/dev/null 2>&1; }

# Wait up to ~5s for MPD to answer. 0 if it answers, 1 if not.
wait_mpd() {
    local i
    for i in $(seq 1 100); do
        mpc status >/dev/null 2>&1 && return 0
        sleep 0.05
    done
    return 1
}

# Start the daemon with the user conf. No waiting: the caller (picker)
# waits alone with wait_mpd so the window opens instantly.
start_mpd() {
    pkill -x mpDris2 2>/dev/null
    pkill -x mpd 2>/dev/null
    rm -f "$HOME/.config/mpd/pid"
    mpd "$MPD_CONF" >/dev/null 2>&1 || die "mpd won't start with $MPD_CONF"
}

# Kill everything: music, daemon, MPRIS bridge, picker window and pid.
kill_all() {
    mpc stop >/dev/null 2>&1
    pkill -x mpDris2 2>/dev/null
    pkill -x mpd 2>/dev/null
    pkill -f "buscador_mp[d]" 2>/dev/null
    rm -f "$HOME/.config/mpd/pid"
}

# Anything playing or queued? Decides whether Esc just closes or kills all.
hay_musica() {
    mpc status 2>/dev/null | grep -q "playing" \
        || [ "$(mpc playlist 2>/dev/null | wc -l)" -gt 0 ]
}

# Deferred MPRIS bridge: only called AFTER picking something (on Esc it
# never runs, so no python process is spent). setsid = own session: it
# survives the window closing (without this it gets SIGHUP from the pty
# and dies instantly).
launch_mpris() {
    [ "$MPRIS" = "true" ] || return 0
    pgrep -x mpDris2 >/dev/null 2>&1 && return 0
    setsid -f nice -n 10 mpDris2 >/dev/null 2>&1 </dev/null
}

# Applies SHUFFLE/REPEAT to current playback.
apply_modes() {
    if [ "$SHUFFLE" = "true" ]; then mpc random on >/dev/null 2>&1;
    else mpc random off >/dev/null 2>&1; fi
    if [ "$REPEAT" = "true" ]; then mpc repeat on >/dev/null 2>&1;
    else mpc repeat off >/dev/null 2>&1; fi
}
