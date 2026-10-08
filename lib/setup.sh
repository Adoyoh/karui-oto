#!/bin/bash
# ============================================================================
# karui-oto · lib/setup.sh — first-run Q&A wizard
# ----------------------------------------------------------------------------
# WHAT:
#   Interactive setup: detects environment, asks with sane defaults
#   (Enter = accept), validates on the spot, writes config.jsonc
#   (backing up any existing one) and offers to show the binds.
#
# WHERE IT FITS:
#   `karui-oto setup`. Sourced AFTER common.sh (uses defaults(),
#   translators from lib/binds.sh, binds_conflict from lib/bindsinstall.sh).
#   Never touches compositor configs or shells — only OUR config file.
#
# HOW TO EXTEND (new question, e.g. "default volume"):
#   1) Ask withask() helper, validate, assign the var. 2) Add the var to
#      defaults() + validate() in common.sh + example + write_config().
#   Keep it Q&A-fast: one question per knob, always with a default.
# ============================================================================

# ask <var> <prompt> <default>: read one line; empty keeps default.
ask() {
    local var="$1" prompt="$2" def="$3" ans
    printf '%s [%s]: ' "$prompt" "$def" >&2
    IFS= read -r ans
    if [ -n "$ans" ]; then printf -v "$var" '%s' "$ans";
    else printf -v "$var" '%s' "$def"; fi
}

# ask_yn <var> <prompt> <Y|N>: yes/no, defaulted. Returns 0 always.
ask_yn() {
    local var="$1" prompt="$2" def="$3" ans hint
    if [ "$def" = "Y" ]; then hint="Y/n"; else hint="y/N"; fi
    printf '%s [%s]: ' "$prompt" "$hint" >&2
    IFS= read -r ans
    case "${ans:-$def}" in
        y|Y|yes|YES|s|S|si|SI) printf -v "$var" '%s' "true" ;;
        *) printf -v "$var" '%s' "false" ;;
    esac
}

# combo_ok <value>: interactive twin of combo_canonical_ok() in common.sh
# (single source of truth lives there; this wrapper keeps setup.sh callers).
combo_ok() {
    combo_canonical_ok "$1"
}

# ask_shortcut <VAR> <mode>: combo with canonical validation + conflict
# check against the compositor file (read-only). Empty skips (unassigned).
# ask_shortcut <VAR> <mode> [comp] [label]: combo with canonical
# validation + conflict check against the compositor file (read-only).
# Empty skips (unassigned). $3 pins the conflict scan to that compositor
# (per-DE overrides asked from another session); default autodetects.
# $4 overrides the prompt label (defaults to the mode).
# Own installed binds are NOT conflicts: same mode+combo is kept silently,
# ours elsewhere just notes the re-apply will move it. Only foreign binds
# loop back with a suggestion.
ask_shortcut() {
    local var="$1" mode="$2" ans comp line label
    comp="${3:-}"; label="${4:-$mode}"
    if [ -z "$comp" ]; then comp="$(detect_compositor 2>/dev/null)" || comp=""; fi
    while :; do
        printf '%s shortcut (empty = none) [%s]: ' "$label" "${!var:-}" >&2
        IFS= read -r ans
        [ -z "$ans" ] && { printf -v "$var" '%s' ""; return 0; }
        combo_ok "$ans" || {
            printf '  invalid form (canonical: Mod+O, Mod+Shift+P)\n' >&2
            continue
        }
        if [ -n "$comp" ] && line="$(binds_conflict "$comp" "$ans" 2>/dev/null)"; then
            case "$line" in
                *karui-oto*)
                    if [[ "$line" == *"karui-oto $mode"* ]]; then
                        printf '  keeping your installed bind: %s\n' "$ans" >&2
                    else
                        printf '  yours elsewhere (%s): re-apply will move it here\n' "$line" >&2
                    fi ;;
                *)
                    printf '  already bound here:\n  %s\n' "$line" >&2
                    printf '  free suggestion here: %s\n' \
                        "$(suggest_combo "$comp" "$(comp_file "$comp")" 2>/dev/null)" >&2
                    continue ;;
            esac
        fi
        printf -v "$var" '%s' "$ans"
        return 0
    done
}

# jstr <s>: JSON-escape a scalar (backslash + quotes). Titles/paths with
# quotes are rare but must not break the file.
jstr() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

# jtri <var>: tri-state knob for write_config: "" (inherit) stays quoted
# empty, true/false go bare. Anything else also goes quoted-empty (validate
# rejects it on load with a clear message, never silently).
jtri() {
    case "${!1:-}" in
        true) printf 'true' ;;
        false) printf 'false' ;;
        *) printf '""' ;;
    esac
}

# write_config: dump current vars as ordered JSONC with a header. Numbers
# and bools go bare, strings quoted, hide[] rebuilt from HIDE_RE, modes{}
# from MODES_*_* (inherited customs survive the roundtrip untouched).
write_config() {
    local dest="$1" hide_items="" p
    # HIDE_RE may be unset on a fresh setup (no config to prefill from, so
    # load_config never ran in this shell): derive defensively, never crash.
    local _hre="${HIDE_RE:-}"
    if [ -z "$_hre" ] && [ -n "${HIDE:-}" ]; then
        if [ -z "${HIDE//[$'\x1f']/}" ]; then _hre="";
        else _hre="${HIDE//$'\x1f'/|}"; fi
    fi
    if [ -n "$_hre" ]; then
        local IFS='|'
        local -a __h
        read -ra __h <<<"$_hre"
        for p in "${__h[@]}"; do
            [ -n "$p" ] || continue
            p="${p//\\/\\\\}"; p="${p//\"/\\\"}"
            hide_items+="${hide_items:+, }\"$p\""
        done
    fi
    if [ -f "$dest" ]; then
        cp -a "$dest" "$dest.bak-$(date +%Y%m%d-%H%M%S)"
        printf 'backup: existing config saved as .bak-*\n' >&2
    fi
    {
        printf '{\n'
        printf '  // karui-oto config (written by `karui-oto setup`; edit freely)\n'
        printf '  "path": %s,\n' "$(jstr "$MUSIC_DIR")"
        printf '  "mpd_conf": %s,\n' "$(jstr "$MPD_CONF")"
        printf '  "terminal": %s,\n' "$(jstr "$TERMINAL")"
        printf '  "term_class": %s,\n' "$(jstr "$TERM_CLASS")"
        printf '  "kitty": {\n'
        printf '    "font": %s,\n' "$(jstr "$KITTY_FONT")"
        printf '    "font_size": %s,\n' "$KITTY_FONT_SIZE"
        printf '    "width": %s,\n' "$KITTY_WIDTH"
        printf '    "height": %s,\n' "$KITTY_HEIGHT"
        printf '    "color": %s,\n' "$(jstr "$KITTY_COLOR")"
        printf '    "transparency": %s\n' "$KITTY_TRANSPARENCY"
        printf '  },\n'
        printf '  "foot": {\n'
        printf '    "font": %s,\n' "$(jstr "$FOOT_FONT")"
        printf '    "font_size": %s,\n' "$FOOT_FONT_SIZE"
        printf '    "width": %s,\n' "$FOOT_WIDTH"
        printf '    "height": %s,\n' "$FOOT_HEIGHT"
        printf '    "color": %s,\n' "$(jstr "$FOOT_COLOR")"
        printf '    "transparency": %s\n' "$FOOT_TRANSPARENCY"
        printf '  },\n'
        printf '  "theme": %s,\n' "$(jstr "$THEME")"
        printf '  "icons": {\n'
        printf '    "search": %s,\n' "$(jstr "$ICONS_SEARCH")"
        printf '    "arrow": %s,\n' "$(jstr "$ICONS_ARROW")"
        printf '    "marker": %s,\n' "$(jstr "$ICONS_MARKER")"
        printf '    "album": %s\n' "$(jstr "$ICONS_ALBUM")"
        printf '  },\n'
        printf '  "shuffle": %s,\n' "$SHUFFLE"
        printf '  "repeat": %s,\n' "$REPEAT"
        printf '  "mpris": %s,\n' "$MPRIS"
        printf '  "min_tracks": %s,\n' "$MIN_TRACKS"
        printf '  "hide": [%s],\n' "$hide_items"
        printf '  "shortcuts": {\n'
        printf '    "songs": %s,\n' "$(jstr "$SHORTCUTS_SONGS")"
        printf '    "artists": %s,\n' "$(jstr "$SHORTCUTS_ARTISTS")"
        printf '    "albums": %s,\n' "$(jstr "$SHORTCUTS_ALBUMS")"
        printf '    "folders": %s,\n' "$(jstr "$SHORTCUTS_FOLDERS")"
        printf '    "kill": %s\n' "$(jstr "$SHORTCUTS_KILL")"
        printf '  },\n'
        # Per-compositor overrides (only sections the user enabled; absent
        # sections inherit the globals above at load time).
        local _wc _wp _wm _wv
        for _wc in NIRI HYPRLAND; do
            _wp="SHORTCUTS_${_wc}_PRESENT"
            [ "${!_wp:-}" = "true" ] || continue
            printf '  "shortcuts_%s": {\n' "${_wc,,}"
            for _wm in SONGS ARTISTS ALBUMS FOLDERS; do
                _wv="SHORTCUTS_${_wc}_${_wm}"
                printf '    "%s": %s,\n' "${_wm,,}" "$(jstr "${!_wv:-}")"
            done
            _wv="SHORTCUTS_${_wc}_KILL"
            printf '    "kill": %s\n' "$(jstr "${!_wv:-}")"
            printf '  },\n'
        done
        printf '  // Per-mode overrides (optional; "" = inherit the globals above).\n'
        printf '  // Example: party songs shuffled, albums in order:\n'
        printf '  //   "songs": { "shuffle": true, "repeat": "", "mpris": "" },\n'
        printf '  "modes": {\n'
        local _m _ml
        for _m in SONGS ARTISTS ALBUMS FOLDERS; do
            _ml="${_m,,}"
            printf '    "%s": { "shuffle": %s, "repeat": %s, "mpris": %s }%s\n' \
                "$_ml" "$(jtri "MODES_${_m}_SHUFFLE")" "$(jtri "MODES_${_m}_REPEAT")" \
                "$(jtri "MODES_${_m}_MPRIS")" "$([ "$_m" = "FOLDERS" ] && printf '' || printf ',')"
        done
        printf '  }\n'
    } > "$dest"
    write_logo_block "$dest"
    printf 'written: %s\n' "$dest" >&2
}

# write_logo_block <dest>: append ", logo[...]" plus the root closing brace
# to a write_config file that currently ends after the "modes" block.
# Customs roundtrip by index: symbols keep text/color/size/
# position, images keep path/transparency/size/position/tint. Empty section
# (LOGO_COUNT=0) writes "logo": [] so the file stays self-documenting.
write_logo_block() {
    local dest="$1" n="${LOGO_COUNT:-0}" i
    {
        printf ',\n'
        printf '  // Logo (kitty only for images; symbols show everywhere).\n'
        printf '  // Each item: exactly one of symbol/image. Symbol: free\n'
        printf '  // text/emoji, color #rrggbb (empty = theme pink), size\n'
        printf '  // small|normal|large, position left|center|right.\n'
        printf '  // Image (kitty window logo): file path, transparency\n'
        printf '  // 0.00-1.00, size 0-100, 9-point position, color = tint.\n'
        printf '  "logo": ['
        if [ "$n" -eq 0 ]; then
            printf ']\n}\n'
            return 0
        fi
        printf '\n'
        for ((i = 0; i < n; i++)); do
            local sym img col size pos tr
            sym="$(eval "printf '%s' \"\${LOGO_${i}_SYMBOL:-}\"")"
            if [ -n "$sym" ]; then
                col="$(eval "printf '%s' \"\${LOGO_${i}_COLOR:-}\"")"
                size="$(eval "printf '%s' \"\${LOGO_${i}_SIZE:-}\"")"
                pos="$(eval "printf '%s' \"\${LOGO_${i}_POSITION:-}\"")"
                printf '    { "symbol": %s, "color": %s, "size": %s, "position": %s }%s\n' \
                    "$(jstr "$sym")" "$(jstr "$col")" "$(jstr "$size")" "$(jstr "$pos")" \
                    "$([ "$i" -eq $((n - 1)) ] && printf '' || printf ',')"
            else
                img="$(eval "printf '%s' \"\${LOGO_${i}_IMAGE:-}\"")"
                tr="$(eval "printf '%s' \"\${LOGO_${i}_TRANSPARENCY:-}\"")"
                size="$(eval "printf '%s' \"\${LOGO_${i}_SIZE:-}\"")"
                pos="$(eval "printf '%s' \"\${LOGO_${i}_POSITION:-}\"")"
                col="$(eval "printf '%s' \"\${LOGO_${i}_COLOR:-}\"")"
                [ -n "$tr" ] || tr="1.0"
                [ -n "$size" ] || size="0"
                [ -n "$pos" ] || pos="bottom-right"
                printf '    { "image": %s, "transparency": %s, "size": %s, "position": %s, "color": %s }%s\n' \
                    "$(jstr "$img")" "$tr" "$size" "$(jstr "$pos")" "$(jstr "$col")" \
                    "$([ "$i" -eq $((n - 1)) ] && printf '' || printf ',')"
            fi
        done
        printf '  ]\n}\n'
    } >> "$dest"
}

# cmd_setup: full wizard. Prefills from the current valid config (keeps
# customs), else fresh defaults. Ends offering the binds output.
cmd_setup() {
    [ -t 0 ] && [ -t 1 ] || die "setup needs an interactive terminal"
    source "$KO_ROOT/lib/binds.sh"
    source "$KO_ROOT/lib/bindsinstall.sh"
    defaults
    if [ -f "$KARUI_OTO_CONFIG" ] && ( load_config ) >/dev/null 2>&1; then
        load_config >/dev/null 2>&1
        printf '(prefilling from your current config)\n' >&2
    fi
    printf 'karui-oto setup — Enter accepts [default]\n' >&2
    local tries=0 ans _oc _om _ov _op _og _yn _want _had
    while :; do
        ask MUSIC_DIR "Music folder" "$MUSIC_DIR"
        expand_tilde MUSIC_DIR
        [ -d "$MUSIC_DIR" ] && break
        printf '  not a directory, try again\n' >&2
        tries=$((tries + 1)); [ "$tries" -ge 3 ] && die "no valid music folder"
    done
    local have_kitty=0 have_foot=0
    command -v kitty >/dev/null 2>&1 && have_kitty=1
    command -v foot >/dev/null 2>&1 && have_foot=1
    if [ "$have_kitty" = "1" ] && [ "$have_foot" = "1" ]; then
        while :; do
            ask TERMINAL "Terminal [kitty|foot]" "$TERMINAL"
            case "$TERMINAL" in kitty|foot) break ;;
                *) printf '  valid: kitty foot\n' >&2 ;; esac
        done
    elif [ "$have_foot" = "1" ]; then
        TERMINAL="foot"; printf '(only foot installed: using foot)\n' >&2
    else
        TERMINAL="kitty"; printf '(only kitty installed: using kitty)\n' >&2
    fi
    local tnames=() tf
    for tf in "$KO_ROOT"/themes/*.sh; do
        tnames+=("$(basename "$tf" .sh)")
    done
    if [ "${#tnames[@]}" -gt 1 ]; then
        printf 'Theme [%s]: %s (number, empty keeps)\n' "$THEME" "${tnames[*]}" >&2
        local PS3="> "
        select tf in "${tnames[@]}"; do
            [ -n "$tf" ] && THEME="$tf"
            break
        done
    fi
    local yn
    [ "$SHUFFLE" = "true" ] && yn="Y" || yn="N"
    ask_yn SHUFFLE "Shuffle" "$yn"
    [ "$REPEAT" = "true" ] && yn="Y" || yn="N"
    ask_yn REPEAT "Repeat" "$yn"
    if command -v mpDris2 >/dev/null 2>&1; then
        [ "$MPRIS" = "true" ] && yn="Y" || yn="N"
    else
        yn="N"
    fi
    ask_yn MPRIS "MPRIS bridge (mpDris2)" "$yn"
    local mtries=0
    while :; do
        ask MIN_TRACKS "Min tracks per artist (1 = show all, 2 = hide one-track guests)" "$MIN_TRACKS"
        [[ "$MIN_TRACKS" =~ ^[0-9]+$ ]] && [ "$MIN_TRACKS" -ge 1 ] && break
        printf '  integer >= 1 (2 hides one-track guests, 1 shows all)\n' >&2
        mtries=$((mtries + 1)); [ "$mtries" -ge 3 ] && die "no valid min_tracks"
    done
    ask_shortcut SHORTCUTS_SONGS songs
    ask_shortcut SHORTCUTS_ARTISTS artists
    ask_shortcut SHORTCUTS_ALBUMS albums
    ask_shortcut SHORTCUTS_FOLDERS folders
    ask_shortcut SHORTCUTS_KILL kill
    # Per-compositor overrides: each DE keeps its own binds, never wiping
    # the other. N = inherit the globals above (section stays absent).
    for _oc in NIRI HYPRLAND; do
        _op="SHORTCUTS_${_oc}_PRESENT"
        if [ "${!_op:-}" = "true" ]; then _yn="Y"; _had="1"; else _yn="N"; _had=""; fi
        ask_yn _want "Different shortcuts for ${_oc,,} than globals? (N = inherit)" "$_yn"
        if [ "$_want" = "true" ]; then
            printf -v "$_op" '%s' "true"
            for _om in SONGS ARTISTS ALBUMS FOLDERS KILL; do
                _ov="SHORTCUTS_${_oc}_${_om}"
                # Fresh section only: prefill globals as working defaults so
                # Enter keeps the global value (explicit clear = unassign).
                # Existing sections keep their values (even intentional empties).
                if [ -z "$_had" ] && [ -z "${!_ov:-}" ]; then
                    _og="SHORTCUTS_${_om}"
                    printf -v "$_ov" '%s' "${!_og:-}"
                fi
                ask_shortcut "$_ov" "${_om,,}" "${_oc,,}" "${_om,,} [${_oc,,}]"
            done
        else
            printf -v "$_op" '%s' ""
            for _om in SONGS ARTISTS ALBUMS FOLDERS KILL; do
                _ov="SHORTCUTS_${_oc}_${_om}"
                printf -v "$_ov" '%s' ""
            done
        fi
    done
    write_config "$KARUI_OTO_CONFIG"
    KARUI_OTO_CONFIG="$KARUI_OTO_CONFIG" load_config  # validate what we wrote
    printf 'program installed OK: %s (config written and valid)\n' "$KARUI_OTO_CONFIG" >&2
    ask_yn show_binds "Show binds now?" "Y"
    # Resolve the compositor ONCE so show + apply agree. Autodetect
    # first; if that fails ask instead of dying inside the wizard.
    local comp=""
    comp="$(detect_compositor 2>/dev/null)" || comp=""
    if [ -z "$comp" ]; then
        printf 'Desktop [niri|hyprland] (empty = skip): ' >&2
        IFS= read -r comp
        case "$comp" in niri|hyprland) : ;; *) comp="" ;; esac
    fi
    if [ -z "$comp" ]; then
        printf 'skipped binds (pick later: karui-oto binds [niri|hyprland])\n' >&2
        printf 'setup done: program installed, binds pending (manual step above)\n' >&2
    else
        [ "$show_binds" = "true" ] && cmd_binds "$comp"
        # Offer assisted install (consent + backup + marked block). Needs
        # at least one EFFECTIVE shortcut for this compositor (global or
        # override), else there is nothing to install.
        local any_key=0 m
        for m in songs artists albums folders kill; do
            [ -n "$(shortcut_for "$m" "$comp")" ] && any_key=1
        done
        if [ "$any_key" = "1" ]; then
            ask_yn do_apply "Install binds into your $comp config now? (backup + marked block)" "N"
            if [ "$do_apply" = "true" ]; then
                binds_apply_flow "$comp"
                printf 'setup done: program installed, binds handled above\n' >&2
            else
                printf 'setup done: program installed, binds skipped by you (karui-oto binds %s to print them)\n' "$comp" >&2
            fi
        else
            printf 'setup done: program installed, no shortcuts assigned for %s (no binds to install)\n' "$comp" >&2
        fi
    fi
    printf 'Open a picker to test.\n' >&2
}