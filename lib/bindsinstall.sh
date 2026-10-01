#!/bin/bash
# ============================================================================
# karui-oto · lib/bindsinstall.sh — binds delivery beyond printing
# ----------------------------------------------------------------------------
# WHAT:
#   Conflict detection, clipboard copy, and assisted --apply/--remove of the
#   generated binds into compositor configs. Printing (cmd_binds) stays the
#   default: NOTHING here writes without explicit user consent.
#
# WHERE IT FITS:
#   bin/karui-oto `binds` subcommand and lib/setup.sh (conflict warnings).
#   Translators (canonical combo -> compositor syntax) live in bin/karui-oto
#   next to cmd_binds; this file handles files, markers, backups, clipboard.
#
# HOW TO EXTEND (new compositor "foo"):
#   1) comp_file(): its config path (or settings:NAME for live stores).
#   2) binds_conflict(): how to spot the combo in its syntax.
#   3) binds_insert(): top-level append is fine unless binds must nest
#      (see niri/openbox cases). 4) validate hook if one exists
#      (niri validate / i3 -C pattern, others print manual reload).
#   5) README + example + COMPATIBILITY.txt row.
#
# SAFETY CONTRACT (read before relaxing any of this):
#   - apply/remove ALWAYS backup first (~/.config/karui-oto/backups/).
#   - niri: brace-aware insert + `niri validate`, auto-restore on failure.
#   - i3: `i3 -C -c file` check, auto-restore on failure.
#   - others (no reliable checker): backup + append/commands + manual
#     reload hint, NEVER silent overwrite. Managed files (/nix/store
#     symlinks) are refused with home-manager instructions.
#   - non-tty stdin refuses --apply (no silent pipes into config files).
#   - conflict = warn + suggest, NEVER auto-replace someone else's bind.
# ============================================================================

# comp_is_file <comp>: 0 if target lives in a text file, 1 if live settings.
comp_is_file() {
    case "$1" in
        niri|hyprland|sway|i3|openbox|bspwm) return 0 ;;
        *) return 1 ;;
    esac
}

# comp_file <comp>: print compositor config path (XDG-aware, no checks).
# Live-setting targets (gnome/kde/...) return settings:NAME (not a path).
comp_file() {
    local base="${XDG_CONFIG_HOME:-$HOME/.config}"
    case "$1" in
        niri)     printf '%s/niri/config.kdl' "$base" ;;
        hyprland) printf '%s/hypr/hyprland.conf' "$base" ;;
        sway)     printf '%s/sway/config' "$base" ;;
        i3)       printf '%s/i3/config' "$base" ;;
        openbox)  printf '%s/openbox/rc.xml' "$base" ;;
        bspwm)    printf '%s/sxhkd/sxhkdrc' "$base" ;;
        gnome|cinnamon|mate) printf 'settings:%s-custom-keybindings' "$1" ;;
        kde)      printf 'settings:kde-kglobalaccel' ;;
        xfce)     printf 'settings:xfce-keyboard-shortcuts' ;;
    esac
}

# managed_file <file>: 0 if the path is a symlink into /nix/store
# (home-manager managed: refuse --apply, print declarative snippet instead).
managed_file() {
    local f="$1" link
    [ -L "$f" ] || return 1
    link="$(readlink "$f")"
    case "$link" in
        /nix/store/*|*/nix/store/*) return 0 ;;
        *) return 1 ;;
    esac
}

# esc_re <s>: escape regex metachars except alphanumerics (for grep -E).
esc_re() { printf '%s' "$1" | sed 's/[][^$.*/\\+?{}()|]/\\&/g'; }

# binds_conflict <comp> <canonical-combo>: print the existing line if the
# combo is already bound to something (any action, including ours).
# rc 0 = conflict (line on stdout), 1 = free, 2 = backend unreadable.
binds_conflict() {
    local comp="$1" combo="$2" file line
    file="$(comp_file "$comp")"
    case "$comp" in
        niri|hyprland|sway|i3|openbox|bspwm)
            [ -r "$file" ] || return 2 ;;
    esac
    case "$comp" in
        niri)
            line="$(grep -E "^[[:space:]]*$(esc_re "$combo")([[:space:]]|\{)" "$file" | head -n 1)" ;;
        hyprland)
            # canonical -> "MODS, KEY" via bin translator (same code path).
            local parts mods key
            parts="$(hypr_parts "$combo")"
            key="${parts##*,}"; mods="${parts%,*}"
            line="$(grep -E "^[[:space:]]*bind[a-z]*[[:space:]]*=[[:space:]]*$(esc_re "$mods")[[:space:]]*,[[:space:]]*$(esc_re "$key")\\b" "$file" | head -n 1)" ;;
        sway|i3)
            local k
            k="$(sway_key "$combo")"
            line="$(grep -F "bindsym $k" "$file" | head -n 1)" ;;
        openbox)
            local ok
            ok="$(openbox_key "$combo")"
            line="$(grep -F "$ok" "$file" | head -n 1)" ;;
        bspwm)
            local sk
            sk="$(sxhkd_key "$combo")"
            line="$(grep -Fx "$sk" "$file" | head -n 1)" ;;
        gnome|cinnamon|mate)
            command -v gsettings >/dev/null 2>&1 || return 2
            local gk base
            gk="$(gnome_key "$combo")"
            line="$(de_gsettings_find_binding "$comp" "$gk" 2>/dev/null)" ;;
        kde)
            local kk f
            kk="$(kde_key "$combo")"
            f="${XDG_CONFIG_HOME:-$HOME/.config}/kglobalaccelrc"
            [ -r "$f" ] || return 2
            line="$(grep -F "$kk" "$f" | head -n 1)" ;;
        xfce)
            command -v xfconf-query >/dev/null 2>&1 || return 2
            local xk
            xk="$(gnome_key "$combo")"
            if xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$xk" >/dev/null 2>&1; then
                line="$(xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$xk" 2>/dev/null)"
            fi ;;
    esac
    if [ -n "$line" ]; then printf '%s\n' "$line"; return 0; fi
    return 1
}

# --- GNOME/Cinnamon/MATE (gsettings custom keybindings) -----------------------
# Schema differs per DE; binding values are compared verbatim (<Super>o).
de_gsettings_schema() {
    case "$1" in
        gnome) printf 'org.gnome.settings-daemon.plugins.media-keys' ;;
        cinnamon) printf 'org.cinnamon.desktop.keybindings' ;;
        mate) printf 'org.mate.SettingsDaemon.plugins.media-keys' ;;
    esac
}
de_gsettings_base() {
    case "$1" in
        gnome) printf '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/' ;;
        cinnamon) printf '/org/cinnamon/desktop/keybindings/custom-keybindings/' ;;
        mate) printf '/org/mate/SettingsDaemon/plugins/media-keys/custom-keybindings/' ;;
    esac
}
# de_gsettings_find_binding <comp> <native-key>: print "name -> command"
# if any custom binding uses that key. rc 1 = free.
de_gsettings_find_binding() {
    local comp="$1" nkey="$2" schema list entry binding cmd name
    schema="$(de_gsettings_schema "$comp")"
    list="$(gsettings get "$schema" custom-keybindings 2>/dev/null)" || return 1
    case "$list" in "@as []"|"[]"|"") return 1 ;; esac
    for entry in $(printf '%s' "$list" | tr -d "[]'," ); do
        case "$entry" in /*/) : ;; *) continue ;; esac
        binding="$(gsettings get "$schema.custom-keybinding:$entry" binding 2>/dev/null | tr -d "'")"
        if [ "$binding" = "$nkey" ]; then
            cmd="$(gsettings get "$schema.custom-keybinding:$entry" command 2>/dev/null)"
            name="$(gsettings get "$schema.custom-keybinding:$entry" name 2>/dev/null)"
            printf '%s binds %s -> %s\n' "$nkey" "$name" "$cmd"
            return 0
        fi
    done
    return 1
}

# suggest_combo <comp>: print a free "Mod+Shift+<letter>" candidate.
# Scans C,O,P,X... no: scans A-Z for a combo absent from the backend.
suggest_combo() {
    local comp="$1" file="$2" L
    # Live stores have no readable file: scan the backend directly.
    case "$comp" in
        gnome|cinnamon|mate|kde|xfce) : ;;
        *) [ -r "$file" ] || { printf 'Mod+Shift+Z\n'; return 0; } ;;
    esac
    for L in O P X C M Q S A D F G H J K L Z B N; do
        binds_conflict "$comp" "Mod+Shift+$L" >/dev/null 2>&1 || { printf 'Mod+Shift+%s\n' "$L"; return 0; }
    done
    printf 'Mod+Shift+F12\n'
}

# clip_copy: stdin -> clipboard. rc 0 ok, 1 no backend (caller prints + hint).
clip_copy() {
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
        wl-copy
    elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard
    elif command -v xsel >/dev/null 2>&1; then
        xsel --clipboard --input
    else
        return 1
    fi
}

# Marker lines per target comment syntax (KDL has no # comments,
# openbox rc.xml needs XML comments).
mark_open() {
    case "$1" in
        niri) printf '// >>> karui-oto >>>' ;;
        openbox) printf '<!-- >>> karui-oto >>> -->' ;;
        *) printf '# >>> karui-oto >>>' ;;
    esac
}
mark_close() {
    case "$1" in
        niri) printf '// <<< karui-oto <<<' ;;
        openbox) printf '<!-- <<< karui-oto <<< -->' ;;
        *) printf '# <<< karui-oto <<<' ;;
    esac
}

# remove_block <comp> <file>: delete our marked block if present. rc 0 always.
# For live stores (<file> is settings:NAME) it removes our karui-oto entries.
remove_block() {
    local comp="$1" file="$2" o c
    case "$comp" in
        gnome|cinnamon|mate) de_gsettings_remove "$comp"; return 0 ;;
        kde) de_kde_remove; return 0 ;;
        xfce) de_xfce_remove; return 0 ;;
    esac
    o="$(mark_open "$comp")"; c="$(mark_close "$comp")"
    [ -f "$file" ] || return 0
    grep -qF "$o" "$file" || return 0
    sed -i "/$(esc_re "$o")/,/$(esc_re "$c")/d" "$file"
}

# de_gsettings_remove <comp>: drop custom entries whose command is karui-oto.
de_gsettings_remove() {
    local comp="$1" schema entry cmd list kept
    command -v gsettings >/dev/null 2>&1 || return 0
    schema="$(de_gsettings_schema "$comp")"
    list="$(gsettings get "$schema" custom-keybindings 2>/dev/null)" || return 0
    kept=""
    for entry in $(printf '%s' "$list" | tr -d "[]'," ); do
        case "$entry" in /*/) : ;; *) continue ;; esac
        cmd="$(gsettings get "$schema.custom-keybinding:$entry" command 2>/dev/null)"
        case "$cmd" in
            *karui-oto*|*karui-media*)
                gsettings reset-recursively "$schema.custom-keybinding:$entry" 2>/dev/null ;;
            *) kept="$kept '$entry'," ;;
        esac
    done
    kept="[${kept%,}]"
    [ "$kept" = "[]" ] && kept="@as []"
    gsettings set "$schema" custom-keybindings "$kept" 2>/dev/null
}

# de_kde_remove: drop karui lines from kglobalaccelrc (backup already taken).
# Matches karui-oto AND karui-media entries (shared karui- prefix).
de_kde_remove() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/kglobalaccelrc"
    [ -f "$f" ] || return 0
    grep -q "karui-" "$f" || return 0
    sed -i '/karui-/d' "$f"
}

# de_xfce_remove: reset our /commands/custom/* properties (karui-oto + media).
de_xfce_remove() {
    local p v
    command -v xfconf-query >/dev/null 2>&1 || return 0
    xfconf-query -c xfce4-keyboard-shortcuts -l -v 2>/dev/null \
    | grep "karui-" | while read -r p v; do
        [ -n "$p" ] && xfconf-query -c xfce4-keyboard-shortcuts -p "$p" --reset 2>/dev/null
    done
}

# backup_file <file>: timestamped copy under our backups dir. Prints path.
backup_file() {
    local file="$1" dest
    dest="$HOME/.config/karui-oto/backups/$(basename "$file")-$(date +%Y%m%d-%H%M%S).bak"
    mkdir -p "$(dirname "$dest")"
    cp -a "$file" "$dest"
    printf '%s\n' "$dest"
}

# backup_settings <comp>: dump a live store into our backups dir. Prints path.
backup_settings() {
    local comp="$1" dest
    dest="$HOME/.config/karui-oto/backups/$comp-settings-$(date +%Y%m%d-%H%M%S).bak"
    mkdir -p "$(dirname "$dest")"
    case "$comp" in
        gnome) command -v dconf >/dev/null 2>&1 && dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "$dest" 2>/dev/null || : > "$dest" ;;
        cinnamon) command -v dconf >/dev/null 2>&1 && dconf dump /org/cinnamon/desktop/keybindings/ > "$dest" 2>/dev/null || : > "$dest" ;;
        mate) command -v dconf >/dev/null 2>&1 && dconf dump /org/mate/SettingsDaemon/plugins/media-keys/ > "$dest" 2>/dev/null || : > "$dest" ;;
        kde) cp -a "${XDG_CONFIG_HOME:-$HOME/.config}/kglobalaccelrc" "$dest" 2>/dev/null || : > "$dest" ;;
        xfce) xfconf-query -c xfce4-keyboard-shortcuts -l -v > "$dest" 2>/dev/null || : > "$dest" ;;
    esac
    printf '%s\n' "$dest"
}

# validate_comp <comp> <file> <bak>: run the native checker when one exists.
# Returns 0 ok / 1 failed (caller restores backup for file targets).
validate_comp() {
    local comp="$1" file="$2" bak="$3"
    case "$comp" in
        niri)
            command -v niri >/dev/null 2>&1 || { printf 'note: niri not running here, skipping live validate\n' >&2; return 0; }
            niri validate >/dev/null 2>&1 || {
                cp -a "$bak" "$file"
                die "niri validate FAILED — restored backup, nothing changed"
            } ;;
        i3)
            if command -v i3 >/dev/null 2>&1; then
                i3 -C -c "$file" >/dev/null 2>&1 || {
                    cp -a "$bak" "$file"
                    die "i3 -C FAILED — restored backup, nothing changed"
                }
            else
                printf 'note: i3 binary missing here, skipping live check (reload with i3-msg restart)\n' >&2
            fi ;;
        openbox)
            printf 'note: openbox has no config checker here (reload with: openbox --reconfigure)\n' >&2 ;;
        bspwm|hyprland|sway)
            printf 'note: no config checker for %s here (reload: %s)\n' "$comp" "$(reload_hint "$comp")" >&2 ;;
    esac
    return 0
}

# reload_hint <comp>: manual reload command for the user.
reload_hint() {
    case "$1" in
        niri) printf 'niri msg action load-config-file' ;;
        hyprland) printf 'hyprctl reload' ;;
        sway) printf 'swaymsg reload' ;;
        i3) printf 'i3-msg restart' ;;
        openbox) printf 'openbox --reconfigure' ;;
        bspwm) printf 'bspc wm -r; pkill -USR1 sxhkd' ;;
        gnome|cinnamon|mate) printf 'no reload needed (gsettings applies instantly)' ;;
        kde) printf 'qdbus org.kde.kglobalaccel /component/kwin reconfigure (or log out/in)' ;;
        xfce) printf 'no reload needed (xfconf applies instantly)' ;;
    esac
}

# insert_block_niri <file> <blockfile>: insert block before the closing brace
# of the TOP-LEVEL binds{} block (brace-aware awk). Dies if no binds block.
# Spawn lines carry balanced {...} pairs so naive counting holds; `niri
# validate` afterwards is the real safety net (auto-restore on failure).
insert_block_niri() {
    local file="$1" block="$2"
    awk -v blk="$block" '
        BEGIN { inb = 0; depth = 0; done = 0 }
        !inb && /^[[:space:]]*binds[[:space:]]*\{/ { inb = 1 }
        inb {
            tmp = $0; gsub(/[^{}]/, "", tmp); line = $0
            for (i = 1; i <= length(tmp); i++) {
                ch = substr(tmp, i, 1)
                if (ch == "{") depth++
                else depth--
            }
            if (depth == 0 && done == 0) {
                while ((getline l < blk) > 0) print l
                close(blk); done = 1; inb = 0
            }
            print line; next
        }
        { print }
        END { if (done == 0) exit 1 }
    ' "$file" > "$file.tmp" || return 1
    mv "$file.tmp" "$file"
}

# insert_block_openbox <file> <blockfile>: insert before </keyboard>.
# Returns 1 if no <keyboard> section (caller appends + warns).
insert_block_openbox() {
    local file="$1" block="$2"
    grep -q "</keyboard>" "$file" || return 1
    awk -v blk="$block" '
        /<\/keyboard>/ && !done {
            while ((getline l < blk) > 0) print l
            close(blk); done = 1
        }
        { print }
    ' "$file" > "$file.tmp" || return 1
    mv "$file.tmp" "$file"
}

# binds_apply <comp> <blockfile>: consent already confirmed by caller.
# Backup -> replace old block -> insert/commands -> validate -> report.
binds_apply() {
    local comp="$1" block="$2" file bak
    file="$(comp_file "$comp")"
    # Live-setting targets ignore the text block: they apply SHORTCUTS_*.
    case "$comp" in
        gnome|cinnamon|mate) de_apply_gsettings "$comp"; return 0 ;;
        kde) de_apply_kde; return 0 ;;
        xfce) de_apply_xfce; return 0 ;;
    esac
    [ -f "$file" ] || die "config file not found: $file (paste manually: karui-oto binds $comp)"
    if managed_file "$file"; then
        die "managed by home-manager ($file -> $(readlink "$file")): refusing to edit. Add the binds snippet to your nix config instead (see binds/ + COMPATIBILITY.txt)"
    fi
    [ -w "$file" ] || die "config file not writable: $file"
    bak="$(backup_file "$file")"
    printf 'backup: %s\n' "$bak" >&2
    remove_block "$comp" "$file"
    if [ "$comp" = "niri" ]; then
        { printf '// >>> karui-oto >>>\n'; cat "$block"; printf '// <<< karui-oto <<<\n'; } > "$block.marked"
        insert_block_niri "$file" "$block.marked" \
            || die "no top-level binds{} block in $file (paste manually)"
        rm -f "$block.marked"
        validate_comp "$comp" "$file" "$bak"
    elif [ "$comp" = "openbox" ]; then
        { printf '<!-- >>> karui-oto >>> -->\n'; cat "$block"; printf '<!-- <<< karui-oto <<< -->\n'; } > "$block.marked"
        insert_block_openbox "$file" "$block.marked" \
            || { cat "$block.marked" >> "$file"; printf 'warning: no <keyboard> block found, appended at end (move inside <keyboard>)\n' >&2; }
        rm -f "$block.marked"
        validate_comp "$comp" "$file" "$bak"
    else
        { mark_open "$comp"; cat "$block"; mark_close "$comp"; } >> "$file"
        validate_comp "$comp" "$file" "$bak"
    fi
    printf 'applied to %s\n' "$file" >&2
    printf 'reload: %s\n' "$(reload_hint "$comp")" >&2
}

# de_apply_gsettings <comp>: create one custom-keybinding per assigned mode.
de_apply_gsettings() {
    local comp="$1" schema base list bak mode combo var nkey path
    command -v gsettings >/dev/null 2>&1 || die "gsettings not found (install it or add binds manually in Settings)"
    schema="$(de_gsettings_schema "$comp")"
    base="$(de_gsettings_base "$comp")"
    bak="$(backup_settings "$comp")"
    printf 'backup: %s\n' "$bak" >&2
    remove_block "$comp" ""
    list="$(gsettings get "$schema" custom-keybindings 2>/dev/null)"
    case "$list" in "@as []"|"[]"|"") list="[]" ;; esac
    for mode in songs artists albums folders kill; do
        var="SHORTCUTS_${mode^^}"; combo="${!var}"
        [ -n "$combo" ] || continue
        nkey="$(gnome_key "$combo")"
        path="${base}karui-oto-${mode}/"
        gsettings set "$schema.custom-keybinding:$path" name "karui-oto $mode" 2>/dev/null \
            || die "gsettings failed for $mode"
        gsettings set "$schema.custom-keybinding:$path" command "$HOME/.local/bin/karui-oto $mode" 2>/dev/null
        gsettings set "$schema.custom-keybinding:$path" binding "$nkey" 2>/dev/null
        case "$list" in *"$path"*) : ;; *) list="${list%]}${list#'['+, }'$path', ]}"; list="$(printf '%s' "$list" | sed "s/\[, /[/")" ;; esac
    done
    # Media keys (fixed table, always): XF86* -> karui-media.
    local _mname _mcmd _mkey
    while read -r _mname _mcmd _mkey; do
        [ -n "$_mname" ] || continue
        path="${base}karui-oto-${_mname}/"
        gsettings set "$schema.custom-keybinding:$path" name "karui-oto $_mname" 2>/dev/null
        gsettings set "$schema.custom-keybinding:$path" command "$HOME/.local/bin/karui-media $_mcmd" 2>/dev/null
        gsettings set "$schema.custom-keybinding:$path" binding "$_mkey" 2>/dev/null
        case "$list" in *"$path"*) : ;; *) list="${list%]}${list#'['+, }'$path', ]}"; list="$(printf '%s' "$list" | sed "s/\[, /[/")" ;; esac
    done <<<"$MEDIA_TABLE"
    # Normalize list: keep old entries + ours, dedup.
    list="$(printf '%s' "$list" | sed "s/, \]/]/;s/\[, /[/")"
    gsettings set "$schema" custom-keybindings "$list" 2>/dev/null \
        || die "gsettings failed writing custom-keybindings list"
    printf 'applied %s custom shortcuts (instant, no reload)\n' "$comp" >&2
}

# de_apply_kde: append Meta+ bindings via kglobalaccelrc + reconfigure hint.
de_apply_kde() {
    local f bak mode combo var nkey tool
    f="${XDG_CONFIG_HOME:-$HOME/.config}/kglobalaccelrc"
    tool=""; command -v kwriteconfig6 >/dev/null 2>&1 && tool="kwriteconfig6"
    [ -z "$tool" ] && command -v kwriteconfig5 >/dev/null 2>&1 && tool="kwriteconfig5"
    [ -n "$tool" ] || die "kwriteconfig5/6 not found (add binds manually in System Settings > Shortcuts)"
    [ -f "$f" ] || : > "$f"
    bak="$(backup_settings kde)"
    printf 'backup: %s\n' "$bak" >&2
    de_kde_remove
    for mode in songs artists albums folders kill; do
        var="SHORTCUTS_${mode^^}"; combo="${!var}"
        [ -n "$combo" ] || continue
        nkey="$(kde_key "$combo")"
        "$tool" --file kglobalaccelrc --group "karui-oto $mode" --key "_launch" "$nkey,none,karui-oto $mode" 2>/dev/null
    done
    local _mname _mcmd _mkey
    while read -r _mname _mcmd _mkey; do
        [ -n "$_mname" ] || continue
        "$tool" --file kglobalaccelrc --group "karui-oto $_mname" --key "_launch" "$_mkey,none,karui-oto $_mname" 2>/dev/null
    done <<<"$MEDIA_TABLE"
    printf 'applied kde shortcuts (reload: %s)\n' "$(reload_hint kde)" >&2
}

# de_apply_xfce: one /commands/custom/<key> property per assigned mode.
de_apply_xfce() {
    local bak mode combo var nkey
    command -v xfconf-query >/dev/null 2>&1 || die "xfconf-query not found (add binds manually in Settings > Keyboard)"
    bak="$(backup_settings xfce)"
    printf 'backup: %s\n' "$bak" >&2
    de_xfce_remove
    for mode in songs artists albums folders kill; do
        var="SHORTCUTS_${mode^^}"; combo="${!var}"
        [ -n "$combo" ] || continue
        nkey="$(gnome_key "$combo")"
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$nkey" --create -t string -s "$HOME/.local/bin/karui-oto $mode" 2>/dev/null \
            || die "xfconf-query failed for $mode ($nkey)"
    done
    local _mname _mcmd _mkey
    while read -r _mname _mcmd _mkey; do
        [ -n "$_mname" ] || continue
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$_mkey" --create -t string -s "$HOME/.local/bin/karui-media $_mcmd" 2>/dev/null \
            || die "xfconf-query failed for $_mname ($_mkey)"
    done <<<"$MEDIA_TABLE"
    printf 'applied xfce shortcuts (instant, no reload)\n' >&2
}
