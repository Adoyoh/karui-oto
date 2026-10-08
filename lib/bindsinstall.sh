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
#   1) comp_file(): its config path.
#   2) binds_conflict(): how to spot the combo in its syntax.
#   3) binds_insert(): top-level append is fine unless binds must nest
#      (see the niri binds{} case). 4) validate hook if one exists
#      (niri validate pattern, else print manual reload).
#   5) README + example + COMPATIBILITY.txt row.
#
# SAFETY CONTRACT (read before relaxing any of this):
#   - apply/remove ALWAYS backup first (~/.config/karui-oto/backups/).
#   - niri: brace-aware insert + `niri validate`, auto-restore on failure.
#   - hyprland: live `hyprctl reload` + `configerrors`, auto-restore.
#   - NEVER silent overwrite. Managed files (/nix/store symlinks) are
#     refused with home-manager instructions.
#   - non-tty stdin refuses --apply (no silent pipes into config files).
#   - conflict = warn + suggest, NEVER auto-replace someone else's bind.
# ============================================================================

# comp_file <comp>: print compositor config path (XDG-aware, no checks).
# hyprland autodetects Lua vs legacy (see hypr_variant in binds.sh).
comp_file() {
    local base="${XDG_CONFIG_HOME:-$HOME/.config}"
    case "$1" in
        niri)     printf '%s/niri/config.kdl' "$base" ;;
        hyprland)
            if [ "$(hypr_variant)" = "lua" ]; then
                printf '%s/hypr/hyprland.lua' "$base"
            else
                printf '%s/hypr/hyprland.conf' "$base"
            fi ;;
    esac
}

# comp_files_all <comp>: every candidate file for sweep/remove (one per line).
# hyprland may hold our block in the Lua file, the legacy conf, or both
# (e.g. migrated setups); the rest have a single path.
comp_files_all() {
    local base="${XDG_CONFIG_HOME:-$HOME/.config}"
    case "$1" in
        hyprland)
            printf '%s/hypr/hyprland.lua\n' "$base"
            printf '%s/hypr/hyprland.conf\n' "$base" ;;
        *) comp_file "$1" ;;
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
    [ -r "$file" ] || return 2
    case "$comp" in
        niri)
            line="$(grep -E "^[[:space:]]*$(esc_re "$combo")([[:space:]]|\{)" "$file" | head -n 1)" ;;
        hyprland)
            if [ "$(hypr_variant)" = "lua" ]; then
                # Lua form: hl.bind(mainMod .. " + SHIFT" .. " + P", hl.dsp...
                # Prefix-match on "hl.bind(<head>, hl.dsp" catches any action
                # on that combo (foreign binds included: that IS a conflict).
                local parts mods key head
                parts="$(hypr_parts "$combo")"
                key="${parts##*,}"; mods="${parts%,*}"
                head="$(hypr_lua_head "$mods" "$key")"
                # Skip Lua comments: a commented bind is not a conflict.
                line="$(grep -F "hl.bind($head, hl.dsp" "$file" | grep -vE '^[[:space:]]*--' | head -n 1)"
            else
                # canonical -> "MODS, KEY" via bin translator (same code path).
                local parts mods key
                parts="$(hypr_parts "$combo")"
                key="${parts##*,}"; mods="${parts%,*}"
                line="$(grep -E "^[[:space:]]*bind[a-z]*[[:space:]]*=[[:space:]]*$(esc_re "$mods")[[:space:]]*,[[:space:]]*$(esc_re "$key")\\b" "$file" | head -n 1)"
            fi ;;
    esac
    if [ -n "$line" ]; then printf '%s\n' "$line"; return 0; fi
    return 1
}

# rules_foreign <comp>: 0 (+ line on stdout) if a NON-ours window rule
# already matches our TERM_CLASS in the target file(s). Warn-only: our own
# previously installed block (marked) is replaced, never a conflict.
rules_foreign() {
    local comp="$1" cls="${TERM_CLASS:-buscador_mpd}" f line
    case "$comp" in
        niri|hyprland) : ;;
        *) return 1 ;;
    esac
    for f in $(comp_files_all "$comp"); do
        [ -r "$f" ] || continue
        if grep -qF -- "$(mark_open_rules "$comp")" "$f"; then
            continue  # ours: will be replaced on apply
        fi
        # Skip commented lines (comment syntax differs per target).
        case "$f" in
            *.kdl) line="$(grep -F "$cls" "$f" | grep -vE '^[[:space:]]*//' | head -n 1)" ;;
            *.lua) line="$(grep -F "$cls" "$f" | grep -vE '^[[:space:]]*(--|#)' | head -n 1)" ;;
            *)     line="$(grep -F "$cls" "$f" | grep -vE '^[[:space:]]*#' | head -n 1)" ;;
        esac
        if [ -n "$line" ]; then printf '%s: %s\n' "$f" "$line"; return 0; fi
    done
    return 1
}

# binds_drift <comp>: compare installed marked blocks vs current config.
# Prints human lines (missing/orphan/moved/media/rules) and returns 1 on
# ANY drift, 0 when installed == configured (silent then). Pure reads.
binds_drift() {
    local comp="$1" mode combo line drift=0
    for mode in songs artists albums folders kill; do
        combo="$(shortcut_for "$mode" "$comp")"
        if [ -z "$combo" ]; then
            # Empty in config but still installed = orphan firing stale.
            line="$(installed_mode_line "$comp" "$mode")"
            if [ -n "$line" ]; then
                printf 'orphan: %s still installed but shortcuts.%s is empty (not in a marked block: delete by hand; --apply only manages its own block)\n' "$line" "$mode"
                drift=1
            fi
            continue
        fi
        if line="$(binds_conflict "$comp" "$combo" 2>/dev/null)"; then
            case "$line" in
                *"karui-oto $mode"*) : ;;  # installed and correct
                *karui-oto*|*karui-media*)
                    printf 'moved: %s runs another mode now (wanted: %s -> %s)\n' "$combo" "$combo" "$mode"
                    drift=1 ;;
                *)
                    printf 'blocked: %s is foreign-bound (%s); %s not installed\n' "$combo" "$line" "$mode"
                    drift=1 ;;
            esac
        else
            printf 'missing: %s -> %s not installed\n' "$combo" "$mode"
            drift=1
        fi
    done
    local _mk
    for _mk in XF86AudioNext XF86AudioPrev XF86AudioPlay; do
        if line="$(binds_conflict "$comp" "$_mk" 2>/dev/null)"; then
            case "$line" in *karui-media*) : ;;
                *) printf 'note: %s also foreign-bound (%s); ours coexists\n' "$_mk" "$line" ;; esac
        else
            printf 'missing: media %s not installed\n' "$_mk"
            drift=1
        fi
    done
    local _rf
    _rf="$(comp_file "$comp")"
    if [ -n "$(gen_rules_block "$comp")" ]; then
        if grep -qF -- "$(mark_open_rules "$comp")" "$_rf" 2>/dev/null; then :;
        else printf 'missing: floating-picker window rules not installed\n'; drift=1; fi
    fi
    return "$drift"
}

# installed_mode_line <comp> <mode>: print our installed line for the mode
# (binds markers region), empty if none. Used for orphan detection.
installed_mode_line() {
    local comp="$1" mode="$2" file
    file="$(comp_file "$comp")"
    [ -r "$file" ] || return 1
    grep -F "karui-oto $mode" "$file" 2>/dev/null | head -n 1
}

# suggest_combo <comp>: print a free "Mod+Shift+<letter>" candidate.
suggest_combo() {
    local comp="$1" file="$2" L
    [ -r "$file" ] || { printf 'Mod+Shift+Z\n'; return 0; }
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
# hyprland-lua needs -- comments: a bare # is the length operator
# in Lua, NOT a comment).
mark_open() {
    case "$1" in
        niri) printf '// >>> karui-oto >>>' ;;
        hyprland) printf '%s >>> karui-oto >>>' "$(hypr_comment)" ;;
        *) printf '# >>> karui-oto >>>' ;;
    esac
}
mark_close() {
    case "$1" in
        niri) printf '// <<< karui-oto <<<' ;;
        hyprland) printf '%s <<< karui-oto <<<' "$(hypr_comment)" ;;
        *) printf '# <<< karui-oto <<<' ;;
    esac
}

# Rules travel in their own marked section: niri rules must live top-level
# (outside binds{}), so one shared block cannot hold binds+rules there.
mark_open_rules() {
    case "$1" in
        niri) printf '// >>> karui-oto rules >>>' ;;
        hyprland) printf '%s >>> karui-oto rules >>>' "$(hypr_comment)" ;;
        *) printf '# >>> karui-oto rules >>>' ;;
    esac
}
mark_close_rules() {
    case "$1" in
        niri) printf '// <<< karui-oto rules <<<' ;;
        hyprland) printf '%s <<< karui-oto rules <<<' "$(hypr_comment)" ;;
        *) printf '# <<< karui-oto rules <<<' ;;
    esac
}

# remove_block <comp> <file>: delete our marked blocks if present. rc 0 always.
# Strips both the binds pair and the rules pair (either may be absent).
remove_block() {
    local comp="$1" file="$2" o c
    [ -f "$file" ] || return 0
    # Both markers required: an unclosed range (crashed edit, hand edit)
    # would otherwise delete to EOF. Open-without-close = warn and skip.
    o="$(mark_open "$comp")"; c="$(mark_close "$comp")"
    if grep -qF -- "$o" "$file"; then
        if grep -qF -- "$c" "$file"; then
            sed -i "/$(esc_re "$o")/,/$(esc_re "$c")/d" "$file"
        else
            printf 'warning: unclosed karui-oto block in %s (leaving it; fix or remove by hand)\n' "$file" >&2
        fi
    fi
    o="$(mark_open_rules "$comp")"; c="$(mark_close_rules "$comp")"
    if grep -qF -- "$o" "$file"; then
        if grep -qF -- "$c" "$file"; then
            sed -i "/$(esc_re "$o")/,/$(esc_re "$c")/d" "$file"
        else
            printf 'warning: unclosed karui-oto rules block in %s (leaving it; fix or remove by hand)\n' "$file" >&2
        fi
    fi
}

# backup_file <file>: timestamped copy under our backups dir. Prints path.
backup_file() {
    local file="$1" dest
    dest="$HOME/.config/karui-oto/backups/$(basename "$file")-$(date +%Y%m%d-%H%M%S).bak"
    mkdir -p "$(dirname "$dest")"
    cp -a "$file" "$dest"
    printf '%s\n' "$dest"
}

# hypr_live: 0 when a Hyprland instance answers hyprctl right now
# (i.e. we are inside a live Hyprland session and can validate for real).
hypr_live() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    hyprctl version >/dev/null 2>&1
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
            }
            # Live reload like the hyprland branch (best-effort, never
            # fatal): without it new binds wait for a manual reload.
            if niri msg action load-config-file >/dev/null 2>&1; then
                printf 'niri reloaded live\n' >&2
            else
                printf 'note: niri not running here (reload: %s)\n' "$(reload_hint "$comp")" >&2
            fi ;;
        i3|openbox|bspwm|sway|gnome|cinnamon|mate|kde|xfce)
            die "unsupported desktop: $comp (karui-oto supports: niri hyprland)" ;;
        hyprland)
            if hypr_live; then
                hyprctl reload >/dev/null 2>&1
                # Our reload surfaces unrelated pre-existing config issues
                # as compositor popups (e.g. rejected monitor scales): not
                # ours, so dismiss them. Notification centers (Noctalia,
                # swaync, mako) are untouched; only Hyprland-internal notes.
                hyprctl dismissnotify >/dev/null 2>&1
                if hyprctl configerrors 2>/dev/null | grep -q '[^[:space:]]'; then
                    cp -a "$bak" "$file"
                    hyprctl dismissnotify >/dev/null 2>&1
                    die "hyprland reports config errors — restored backup, nothing changed (hyprctl configerrors)"
                fi
                printf 'hyprland reloaded live, no config errors\n' >&2
            else
                printf 'note: Hyprland not running here, skipping live check (reload: %s)\n' "$(reload_hint "$comp")" >&2
            fi ;;
    esac
    return 0
}

# reload_hint <comp>: manual reload command for the user.
reload_hint() {
    case "$1" in
        niri) printf 'niri msg action load-config-file' ;;
        *) printf 'hyprctl reload' ;;
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

# binds_sync [comp]: reconcile shortcuts{} into the compositor, silently.
# No drift -> exit 0 doing nothing. Drift -> backup + regenerate + validate.
# Never prompts, never dies loudly: returns 1 on any problem so a background
# caller (or --sync) can report it while the picker itself is unaffected.
# Modes colliding with FOREIGN binds are skipped this round (their lines
# stay as they were); media keys always install (coexistence, warn-only).
binds_sync() {
    local comp="${1:-}" file tmp rtmp mode combo var line skip
    if [ -z "$comp" ]; then
        comp="$(detect_compositor 2>/dev/null)" || return 0
    fi
    case "$comp" in niri|hyprland) : ;; *) return 0 ;; esac
    file="$(comp_file "$comp")"
    [ -f "$file" ] && [ -w "$file" ] || return 0
    # Single drift scan: its text goes to our caller (a background hook
    # discards it; manual --sync shows it).
    local dinfo drc=0
    dinfo="$(binds_drift "$comp" 2>&1)" || drc="$?"
    if [ "$drc" -eq 0 ]; then return 0; fi
    printf '%s\n' "$dinfo" >&2
    # Serialize concurrent syncs (two pickers, setup racing): loser skips.
    local lockdir="/tmp/karui-oto-sync.lockdir"
    if ! mkdir "$lockdir" 2>/dev/null; then
        local _op
        _op="$(cat "$lockdir/pid" 2>/dev/null)"
        if [[ "$_op" =~ ^[0-9]+$ ]] && kill -0 "$_op" 2>/dev/null; then
            return 0
        fi
        rm -rf "$lockdir"
        mkdir "$lockdir" 2>/dev/null || return 0
    fi
    printf '%s' "$$" > "$lockdir/pid" 2>/dev/null || { rm -rf "$lockdir"; return 0; }
    trap 'rm -rf "$lockdir"' RETURN
    # Stage with foreign-colliding modes filtered out (subshell so the
    # caller's SHORTCUTS_* stay intact for the running picker).
    tmp="$(mktemp)"; rtmp="$(mktemp)"
    (
        for mode in songs artists albums folders kill; do
            var="SHORTCUTS_${mode^^}"; combo="${!var}"
            [ -n "$combo" ] || continue
            if line="$(binds_conflict "$comp" "$combo" 2>/dev/null)"; then
                case "$line" in *karui-oto*|*karui-media*) : ;;
                    *) printf -v "SHORTCUTS_${mode^^}" '%s' "" ;;
                esac
            fi
        done
        gen_binds_block "$comp" > "$tmp"
        gen_rules_block "$comp" > "$rtmp"
    )
    binds_apply "$comp" "$tmp" "$rtmp" >/dev/null 2>&1
    local rc="$?"
    rm -f "$tmp" "$rtmp"
    trap - RETURN
    rm -rf "$lockdir"
    if [ "$rc" -ne 0 ]; then return "$rc"; fi
    # Post-apply re-scan: managed content must have converged. Leftovers
    # (e.g. hand-pasted lines outside our markers) keep rc 2 so callers
    # can tell "applied, but still needs a hand".
    if binds_drift "$comp" >/dev/null 2>&1; then
        return 0
    fi
    return 2
}

# binds_apply <comp> <blockfile> [rulesfile]: consent already confirmed.
# Backup -> replace old blocks -> insert/append -> validate -> report.
# The rules file (floating-picker window rules, may be empty) travels in its
# own marked section: top-level for niri (never inside binds{}), appended
# everywhere else.
binds_apply() {
    local comp="$1" block="$2" rules="${3:-}" file bak
    file="$(comp_file "$comp")"
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
        if [ -n "$rules" ] && [ -s "$rules" ]; then
            { printf '\n// >>> karui-oto rules >>>\n'; cat "$rules"; printf '// <<< karui-oto rules <<<\n'; } >> "$file"
        fi
        validate_comp "$comp" "$file" "$bak"
    else
        { mark_open "$comp"; printf '\n'; cat "$block"; mark_close "$comp"; printf '\n'; } >> "$file"
        if [ -n "$rules" ] && [ -s "$rules" ]; then
            { mark_open_rules "$comp"; printf '\n'; cat "$rules"; mark_close_rules "$comp"; printf '\n'; } >> "$file"
        fi
        validate_comp "$comp" "$file" "$bak"
    fi
    printf 'applied to %s\n' "$file" >&2
    printf 'reload: %s\n' "$(reload_hint "$comp")" >&2
}
