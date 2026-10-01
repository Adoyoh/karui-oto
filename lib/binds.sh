#!/bin/bash
# ============================================================================
# karui-oto · lib/binds.sh — keybind generation (pure text, no files)
# ----------------------------------------------------------------------------
# WHAT:
#   Canonical shortcut ("Mod+O") -> compositor syntax translators plus
#   cmd_binds (print) and gen_binds_block (raw lines for --apply).
#   bindsinstall.sh (files/markers/backups) consumes this; it never writes.
#
# CANONICAL FORM (validated in common.sh before reaching here):
#   Mod+O, Mod+Shift+P, Ctrl+Alt+T, bare F12 / XF86AudioPlay.
#   "Mod" means the compositor's main modifier ($mainMod/$mod, usually Super).
#
# SUPPORTED TARGETS (see COMPATIBILITY.txt):
#   Text configs (file append): niri hyprland sway i3 openbox bspwm
#   Live settings (commands):   gnome kde xfce cinnamon mate
# ============================================================================

# All known targets in stable order (used by help/setup/completion).
SUPPORTED_COMPS="niri hyprland sway i3 gnome kde xfce cinnamon mate openbox bspwm"

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
        *sway*) printf 'sway' ;;
        *i3*)   printf 'i3' ;;
        *gnome*) printf 'gnome' ;;
        *kde*|*plasma*) printf 'kde' ;;
        *xfce*) printf 'xfce' ;;
        *cinnamon*) printf 'cinnamon' ;;
        *mate*) printf 'mate' ;;
        *lxqt*) printf 'lxqt' ;;
        *openbox*) printf 'openbox' ;;
        *bspwm*) printf 'bspwm' ;;
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

# sway/i3: "Mod+Shift+P" -> "$mod+Shift+p". Bare tokens (F12, XF86*)
# pass through untouched (keysyms are case-sensitive there).
sway_key() {
    local combo="$1"
    case "$combo" in
        *+*) : ;;
        *) printf '%s' "$combo"; return 0 ;;
    esac
    local first="${combo%%+*}" key="${combo##*+}"
    [ "$first" = "Mod" ] && first="\$mod"
    # "${combo%$key}" keeps the trailing "+" of the mods part, so join
    # WITHOUT adding another one (else "$mod++o").
    printf '%s%s' "${combo%$key}" "${key,,}" | sed "s/^[^+]*/$first/"
}
# NOTE: the sed above swaps only the first token; mods keep their case
# (sway convention: $mod+Shift+p).

# GNOME/XFCE/Cinnamon/MATE (gsettings/xfconf): "Mod+Shift+P" -> "<Super><Shift>p".
# Bare keys (F12, XF86AudioPlay) pass through. Letters go lowercase.
gnome_key() {
    local combo="$1" out="" key mods
    case "$combo" in
        *+*) : ;;
        *) printf '%s' "$combo"; return 0 ;;
    esac
    key="${combo##*+}"; mods="${combo%+$key}"
    out="$(printf '%s' "$mods" | sed -e 's/Mod/<Super>/g' -e 's/Shift/<Shift>/g' -e 's/Ctrl/<Ctrl>/g' -e 's/Alt/<Alt>/g' -e 's/+//g')"
    case "$key" in XF86*|F[0-9]*|space|Tab|Escape|Return|BackSpace|Delete|Insert|Home|End|Page_Up|Page_Down) printf '%s%s' "$out" "$key" ;;
        *) printf '%s%s' "$out" "${key,,}" ;; esac
}

# KDE (kglobalaccel): "Mod+Shift+P" -> "Meta+Shift+P". Letters stay UPPER.
kde_key() {
    local combo="$1" out
    out="$(printf '%s' "$combo" | sed -e 's/Mod/Meta/g')"
    printf '%s' "$out"
}

# Openbox (rc.xml): "Mod+Shift+P" -> "W-S-P". Bare keys pass through.
openbox_key() {
    local combo="$1" out
    case "$combo" in
        *+*) : ;;
        *) printf '%s' "$combo"; return 0 ;;
    esac
    out="$(printf '%s' "$combo" | sed -e 's/Mod/W/g' -e 's/Shift/S/g' -e 's/Ctrl/C/g' -e 's/Alt/A/g' -e 's/\+/-/g')"
    printf '%s' "$out"
}

# sxhkd (bspwm): "Mod+Shift+P" -> "super+shift+p". Bare keysyms (XF86*, F*)
# pass through untouched (case-sensitive there); other bare words lowercase.
sxhkd_key() {
    local combo="$1" out key mods
    case "$combo" in
        *+*) : ;;
        XF86*|F[0-9]*) printf '%s' "$combo"; return 0 ;;
        *) printf '%s' "${combo,,}"; return 0 ;;
    esac
    key="${combo##*+}"; mods="${combo%+$key}"
    out="$(printf '%s' "$mods" | sed -e 's/Mod/super/g' -e 's/Shift/shift/g' -e 's/Ctrl/ctrl/g' -e 's/Alt/alt/g' -e 's/\+/+/g')"
    case "$key" in XF86*) printf '%s+%s' "$out" "$key" ;;
        *) printf '%s+%s' "$out" "${key,,}" ;; esac
}

bind_niri() {  # <mode> <combo>
    printf '    %s hotkey-overlay-title="%s" { spawn "bash" "-c" "~/.local/bin/karui-oto %s"; }\n' \
        "$2" "$(bind_title "$1")" "$1"
}

bind_hyprland() {  # <mode> <combo>
    # Empty mods ("F12") is valid hyprland ("bind = , F12, ...").
    local parts key mods
    parts="$(hypr_parts "$2")"
    key="${parts##*,}"; mods="${parts%,*}"
    printf 'bind = %s, %s, exec, ~/.local/bin/karui-oto %s\n' "$mods" "$key" "$1"
}

bind_sway() {  # <mode> <combo> (i3 shares the shape; --no-startup-id added by caller)
    printf 'bindsym %s exec ~/.local/bin/karui-oto %s\n' "$(sway_key "$2")" "$1"
}

# DE printers: one line per mode with the native key + exact command.
# GNOME/Cinnamon/MATE share gsettings syntax; XFCE uses xfconf key names
# (same <Super> style); KDE uses Meta+ form; Openbox/sxhkd are file lines.
bind_gnome() {  # <mode> <combo>
    printf '# %s: key %s -> command: ~/.local/bin/karui-oto %s (Settings > Keyboard > Custom Shortcuts)\n' \
        "$1" "$(gnome_key "$2")" "$1"
}

bind_cinnamon() { bind_gnome "$@"; }
bind_mate() { bind_gnome "$@"; }

bind_kde() {  # <mode> <combo>
    printf '# %s: key %s -> command: ~/.local/bin/karui-oto %s (System Settings > Shortcuts > Custom)\n' \
        "$1" "$(kde_key "$2")" "$1"
}

bind_xfce() {  # <mode> <combo>
    printf '# %s: key %s -> command: ~/.local/bin/karui-oto %s (Settings > Keyboard > Application Shortcuts)\n' \
        "$1" "$(gnome_key "$2")" "$1"
}

bind_openbox() {  # <mode> <combo> (rc.xml keybind fragment)
    printf '    <!-- karui-oto %s: -->\n    <keybind key="%s"><action name="Execute"><command>~/.local/bin/karui-oto %s</command></action></keybind>\n' \
        "$1" "$(openbox_key "$2")" "$1"
}

bind_bspwm() {  # <mode> <combo> (sxhkdrc fragment)
    printf '%s\n    ~/.local/bin/karui-oto %s\n' "$(sxhkd_key "$2")" "$1"
}

# gen_binds_block <comp>: raw bind lines (no header) for printing/applying.
# Empty shortcuts become "# ..." placeholders (comment-safe everywhere;
# openbox lines are XML comments, still safe).
gen_binds_block() {
    local comp="$1" mode combo var
    for mode in songs artists albums folders kill; do
        var="SHORTCUTS_${mode^^}"
        combo="${!var}"
        if [ -z "$combo" ]; then
            if [ "$comp" = "niri" ]; then
                printf '// %s: (no shortcut — empty in config)\n' "$mode"
            elif [ "$comp" = "openbox" ]; then
                printf '<!-- %s: (no shortcut — empty in config) -->\n' "$mode"
            else
                printf '# %s: (no shortcut — empty in config)\n' "$mode"
            fi
            continue
        fi
        if [ "$comp" = "i3" ]; then
            printf 'bindsym %s exec --no-startup-id ~/.local/bin/karui-oto %s\n' \
                "$(sway_key "$combo")" "$mode"
        else
            "bind_$comp" "$mode" "$combo"
        fi
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
                printf 'bindel = , %s, exec, ~/.local/bin/karui-media %s\n' "$key" "$cmd" ;;
            sway)
                printf 'bindsym %s exec ~/.local/bin/karui-media %s\n' "$key" "$cmd" ;;
            i3)
                printf 'bindsym %s exec --no-startup-id ~/.local/bin/karui-media %s\n' "$key" "$cmd" ;;
            gnome|cinnamon|mate)
                printf '# %s: key %s -> command: ~/.local/bin/karui-media %s\n' "$name" "$key" "$cmd" ;;
            kde)
                printf '# %s: key %s -> command: ~/.local/bin/karui-media %s\n' "$name" "$key" "$cmd" ;;
            xfce)
                printf '# %s: key %s -> command: ~/.local/bin/karui-media %s\n' "$name" "$key" "$cmd" ;;
            openbox)
                printf '    <!-- karui-oto %s: -->\n    <keybind key="%s"><action name="Execute"><command>~/.local/bin/karui-media %s</command></action></keybind>\n' \
                    "$name" "$key" "$cmd" ;;
            bspwm)
                printf '%s\n    ~/.local/bin/karui-media %s\n' "$key" "$cmd" ;;
        esac
    done <<<"$MEDIA_TABLE"
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
        printf '// karui-oto binds for %s (generated; paste into your compositor config)\n' "$comp"
    elif [ "$comp" = "openbox" ]; then
        printf '<!-- karui-oto binds for %s (generated; paste inside <keyboard> in rc.xml) -->\n' "$comp"
    elif [ "$comp" = "gnome" ] || [ "$comp" = "cinnamon" ] || [ "$comp" = "mate" ] || [ "$comp" = "kde" ] || [ "$comp" = "xfce" ]; then
        printf '# karui-oto binds for %s (generated; add in Settings > Keyboard > Custom Shortcuts)\n' "$comp"
    else
        printf '# karui-oto binds for %s (generated; paste into your compositor config)\n' "$comp"
    fi
    gen_binds_block "$comp"
}
