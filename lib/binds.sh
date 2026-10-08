#!/bin/bash
# ============================================================================
# karui-oto · lib/binds.sh — keybind generation (pure text, no files)
# ----------------------------------------------------------------------------
# WHAT:
#   Canonical shortcut ("Mod+O") -> compositor syntax translators plus
#   cmd_binds (print) and gen_binds_block (raw lines for --apply).
#   bindsinstall.sh (files/markers/backups) consumes this; it never writes.
#
# SCOPE: niri + hyprland only (other desktops were cut: their configs differ
# too much to track reliably; git history keeps the old translators).
#
# CANONICAL FORM (validated in common.sh before reaching here):
#   Mod+O, Mod+Shift+P, Ctrl+Alt+T, bare F12 / XF86AudioPlay.
#   "Mod" means the compositor's main modifier ($mainMod/$mod, usually Super).
#
# SUPPORTED TARGETS (see COMPATIBILITY.txt):
#   Text configs (file append): niri hyprland
# ============================================================================

# All known targets in stable order (used by help/setup/completion).
SUPPORTED_COMPS="niri hyprland"

bind_title() {  # mode -> overlay title (niri)
    case "$1" in
        songs)   printf 'karui-oto: search song' ;;
        artists) printf 'karui-oto: search artist' ;;
        albums)  printf 'karui-oto: search album' ;;
        folders) printf 'karui-oto: search folder' ;;
        kill)    printf 'karui-oto: kill everything' ;;
        media-next) printf 'karui-oto: next track' ;;
        media-prev) printf 'karui-oto: previous track' ;;
        media-play) printf 'karui-oto: play/pause' ;;
    esac
}

# Fixed media table: entry name | karui-media arg | native XF86 key.
# Always installed (no config knob): a music program owns its media keys.
MEDIA_TABLE="media-next next XF86AudioNext
media-prev prev XF86AudioPrev
media-play play-pause XF86AudioPlay"

detect_compositor() {
    local d="${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-}"
    case "${d,,}" in
        *niri*) printf 'niri' ;;
        *hypr*) printf 'hyprland' ;;
        *) return 1 ;;
    esac
}

# is_comp <name>: 0 if supported target, 1 otherwise.
is_comp() {
    case " $SUPPORTED_COMPS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# hypr_variant: lua | legacy. Hyprland >= 0.55 speaks Lua (hyprland.lua);
# older ones speak the legacy hyprland.conf. Autodetect by files first
# (a stray legacy .conf next to a live .lua must not win), then by the
# installed binary version, defaulting to lua for fresh installs.
hypr_variant() {
    local base="${XDG_CONFIG_HOME:-$HOME/.config}"
    [ -f "$base/hypr/hyprland.lua" ] && { printf 'lua'; return 0; }
    [ -f "$base/hypr/hyprland.conf" ] && { printf 'legacy'; return 0; }
    if command -v hyprland >/dev/null 2>&1; then
        local ver maj min
        ver="$(hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n 1)"
        maj="${ver%%.*}"; min="${ver#*.}"
        if [ -n "$maj" ] && [ -n "$min" ] \
            && { [ "$maj" -ge 1 ] || { [ "$maj" -eq 0 ] && [ "$min" -ge 55 ]; }; }; then
            printf 'lua'; return 0
        fi
        printf 'legacy'; return 0
    fi
    printf 'lua'
}

# hypr_comment: line-comment token for generated hyprland text.
# Lua (-- ) on 0.55+ setups; legacy hash (#) before that. NOTE: a bare #
# is NOT a comment in Lua (length operator) — emitting it into hyprland.lua
# is a hard config error, so every generated comment goes through here.
hypr_comment() {
    if [ "$(hypr_variant)" = "lua" ]; then printf -- '--'; else printf '#'; fi
}

# hyprland: "Mod+Shift+P" -> mods "$mainMod SHIFT", key "P".
hypr_parts() {
    local combo="$1" mods="" key="" p
    IFS='+' read -ra _hp <<<"$combo"
    local n=${#_hp[@]}
    key="${_hp[$((n-1))]}"
    # X keysyms are case-sensitive (XF86AudioStop); single letters go UPPER.
    case "$key" in XF86*) : ;; *) key="${key^^}" ;; esac
    for ((i=0; i<n-1; i++)); do
        p="${_hp[$i]}"
        if [ "$p" = "Mod" ]; then
            mods+='$mainMod '  # exact case: hyprland vars are case-sensitive
        else
            mods+="${p^^} "
        fi
    done
    printf '%s,%s' "${mods% }" "$key"
}

bind_niri() {  # <mode> <combo>
    printf '    %s hotkey-overlay-title="%s" { spawn "bash" "-c" "~/.local/bin/karui-oto %s"; }\n' \
        "$2" "$(bind_title "$1")" "$1"
}

# hypr_lua_head <mods> <key>: legacy hypr_parts output ("$mainMod SHIFT", "P")
# -> Lua bind head expression: 'mainMod .. " + SHIFT" .. " + P"'.
# Bare keys (no mods, e.g. XF86AudioNext) become '"XF86AudioNext"'.
hypr_lua_head() {
    local mods="$1" key="$2" t out=""
    for t in $mods; do
        [ "$t" = '$mainMod' ] && t='mainMod'
        [ -z "$out" ] && out="$t" || out="$out .. \" + $t\""
    done
    if [ -z "$out" ]; then printf '"%s"' "$key";
    else printf '%s .. " + %s"' "$out" "$key"; fi
}

bind_hyprland() {  # <mode> <combo> (legacy or Lua by autodetect)
    if [ "$(hypr_variant)" = "lua" ]; then bind_hyprland_lua "$@"; return 0; fi
    # Empty mods ("F12") is valid hyprland ("bind = , F12, ...").
    local parts key mods
    parts="$(hypr_parts "$2")"
    key="${parts##*,}"; mods="${parts%,*}"
    printf 'bind = %s, %s, exec, %s/.local/bin/karui-oto %s\n' "$mods" "$key" "$HOME" "$1"
}

bind_hyprland_lua() {  # <mode> <combo>
    # exec_cmd runs without tilde expansion: absolute $HOME, expanded now.
    local parts key mods
    parts="$(hypr_parts "$2")"
    key="${parts##*,}"; mods="${parts%,*}"
    printf 'hl.bind(%s, hl.dsp.exec_cmd("%s/.local/bin/karui-oto %s"))\n' \
        "$(hypr_lua_head "$mods" "$key")" "$HOME" "$1"
}

# gen_binds_block <comp>: raw bind lines (no header) for printing/applying.
# Empty shortcuts become comment placeholders (comment-safe in both syntaxes).
gen_binds_block() {
    local comp="$1" mode combo
    for mode in songs artists albums folders kill; do
        combo="$(shortcut_for "$mode" "$comp")"
        if [ -z "$combo" ]; then
            if [ "$comp" = "niri" ]; then
                printf '// %s: (no shortcut — empty in config)\n' "$mode"
            else
                printf '%s %s: (no shortcut — empty in config)\n' "$(hypr_comment)" "$mode"
            fi
            continue
        fi
        "bind_$comp" "$mode" "$combo"
    done
    # Media keys (XF86): always installed, same player bridge everywhere.
    # Real lines (not hints) so --apply/--remove roundtrips them like modes.
    gen_media_block "$comp"
}

# gen_media_block <comp>: the 3 XF86 lines for karui-media (fixed table).
gen_media_block() {
    local comp="$1" name cmd key
    while read -r name cmd key; do
        [ -n "$name" ] || continue
        case "$comp" in
            niri)
                printf '    %s hotkey-overlay-title="%s" { spawn "bash" "-c" "~/.local/bin/karui-media %s"; }\n' \
                    "$key" "$(bind_title "$name")" "$cmd" ;;
            hyprland)
                if [ "$(hypr_variant)" = "lua" ]; then
                    printf 'hl.bind("%s", hl.dsp.exec_cmd("%s/.local/bin/karui-media %s"), { locked = true, repeating = true })\n' \
                        "$key" "$HOME" "$cmd"
                else
                    printf 'bindel = , %s, exec, %s/.local/bin/karui-media %s\n' "$key" "$HOME" "$cmd"
                fi ;;
        esac
    done <<<"$MEDIA_TABLE"
}

# gen_rules_block <comp>: floating-picker window rules anchored at TERM_CLASS.
# Installed ALWAYS together with the binds (same apply flow, own markers).
# The picker then opens big and centered instead of squeezed into tiling.
# Empty output = compositor without automatic float (binds only, note it).
gen_rules_block() {
    local comp="$1" cls="${TERM_CLASS:-buscador_mpd}"
    case "$comp" in
        niri)
            printf 'window-rule {\n    match app-id="%s"\n    open-floating true\n    default-column-width { fixed 1200; }\n    default-window-height { fixed 700; }\n}\n' "$cls" ;;
        hyprland)
            if [ "$(hypr_variant)" = "lua" ]; then
                # NOTE: size takes exact pixels ({ 1200, 700 }): percent
                # strings are silently ignored by hl.window_rule in 0.55
                # (verified live: { 1100, 650 } applies, "90% 90%" doesn't).
                printf 'hl.window_rule({\n    name = "karui-oto",\n    match = { class = "%s" },\n    float = true,\n    size = { 1200, 700 },\n    center = true,\n})\n' "$cls"
            else
                printf 'windowrule = float,class:%s\nwindowrule = size 90%% 90%%,class:%s\nwindowrule = center,class:%s\n' \
                    "$cls" "$cls" "$cls"
            fi ;;
    esac
}

# cmd_binds [compositor]: header + block to stdout. Used by `binds`,
# `--copy` (piped to clipboard) and `--apply` (via temp blockfile).
cmd_binds() {
    local comp="${1:-}"
    if [ -z "$comp" ]; then
        comp="$(detect_compositor)" \
            || die "cannot detect desktop (set it: binds [niri|hyprland|sway|i3|gnome|kde|xfce|cinnamon|mate|openbox|bspwm])"
    fi
    is_comp "$comp" || die "unknown desktop: $comp (valid: $SUPPORTED_COMPS)"
    if [ "$comp" = "niri" ]; then
        printf '// karui-oto binds for %s (generated; binds go inside binds{}, rules are top-level)\n' "$comp"
    elif [ "$(hypr_variant)" = "lua" ]; then
        printf -- '-- karui-oto binds for %s (Lua syntax; append to hyprland.lua)\n' "$comp"
    else
        printf '# karui-oto binds for %s (legacy syntax; paste into hyprland.conf)\n' "$comp"
    fi
    gen_binds_block "$comp"
    # Floating-picker rules travel with the binds (same file/block flow).
    local rules
    rules="$(gen_rules_block "$comp")"
    if [ -n "$rules" ]; then
        if [ "$comp" = "niri" ]; then
            printf '// window rules for %s (top-level, outside binds{})\n' "$comp"
        elif [ "$comp" = "hyprland" ]; then
            printf '%s window rules for %s (floating picker)\n' "$(hypr_comment)" "$comp"
        else
            printf '# window rules for %s (floating picker)\n' "$comp"
        fi
        printf '%s\n' "$rules"
    fi
}
