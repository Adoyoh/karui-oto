#!/bin/bash
# ============================================================================
# karui-oto · lib/doctor.sh — read-only health check
# ----------------------------------------------------------------------------
# WHAT:
#   Verifies dependencies, config, MPD, fonts and installed binds. Every
#   finding prints [OK]/[WARN]/[FAIL] plus its exact remediation. Read-only
#   EXCEPT one consented write: when shortcuts exist but the current
#   compositor never got them (fresh compositor), doctor offers to install
#   them ([y/N], default N, backup + validation). Piped runs never write.
#
# WHERE IT FITS:
#   `karui-oto doctor`. Sourced AFTER common.sh (uses load_config result
#   when it works; when the config itself is broken that becomes finding #1
#   and doctor stops there). Needs lib/binds.sh translators for the binds
#   check (sourced below, idempotent).
#
# HOW TO EXTEND (new check, e.g. "foot server running"):
#   Copy a check block: probe, one of ok()/warn()/fail() with remediation,
#   bump the matching counter. Keep probes read-only: no mpc commands that
#   alter state, no file writes, no process launches beyond queries.
# ============================================================================

SP_OK=0; SP_WARN=0; SP_FAIL=0
ok()   { SP_OK=$((SP_OK + 1));   printf '[OK]   %s\n' "$1"; }
warn() { SP_WARN=$((SP_WARN + 1)); printf '[WARN] %s\n' "$1"; }
fail() { SP_FAIL=$((SP_FAIL + 1)); printf '[FAIL] %s\n' "$1"; }

cmd_doctor() {
    source "$KO_ROOT/lib/binds.sh"
    source "$KO_ROOT/lib/bindsinstall.sh"  # comp_file/binds_conflict (translators above)
    # 0. Config itself (fatal finding #1, but NOT a stop: config-independent
    # checks below still run so one broken file never hides everything else).
    # load_config dies on failure, so it runs in a subshell first: the
    # [FAIL]/result accounting stays reachable. Full stderr block shown
    # (jconfig prints error + offending lines + hint). Second call loads
    # for real when the first passed.
    local CONFIG_OK=1
    if ! ( load_config ) >/dev/null 2>/tmp/ko_doc.err; then
        fail "config invalid. Fix the message below (or run karui-oto setup)"
        cat /tmp/ko_doc.err >&2
        rm -f /tmp/ko_doc.err
        CONFIG_OK=0
    else
        rm -f /tmp/ko_doc.err
        load_config >/dev/null 2>&1
        ok "config loads: $KARUI_OTO_CONFIG"
    fi

    # 1. Hard deps (+ fzf feature probe).
    local missing=0 c
    for c in bash mpc mpd fzf python3; do
        command -v "$c" >/dev/null 2>&1 || { fail "missing: $c"; missing=1; }
    done
    [ "$missing" -eq 0 ] && ok "hard deps present (bash mpc mpd fzf python3)"
    if fzf --help 2>&1 | grep -q "accept-nth"; then
        ok "fzf supports --accept-nth"
    else
        fail "fzf too old (no --accept-nth). Fix: upgrade fzf (~2024+)"
    fi
    if [ "$CONFIG_OK" = "1" ]; then
        if command -v "$TERMINAL" >/dev/null 2>&1; then
            ok "terminal installed: $TERMINAL"
        else
            fail "terminal missing: $TERMINAL. Fix: install it or set terminal= accordingly"
        fi
    else
        printf '[INFO] terminal check skipped (config invalid)\n'
    fi

    # 2. Optionals (never fatal).
    command -v mpDris2 >/dev/null 2>&1 \
        && ok "mpDris2 present (MPRIS)" \
        || warn "no mpDris2: MPRIS metadata off (or set mpris=false to silence)"
    command -v playerctl >/dev/null 2>&1 \
        && ok "playerctl present (media keys prefer MPRIS, fall back to mpc)" \
        || warn "no playerctl: karui-media controls MPD via mpc only (install playerctl for MPRIS)"

    # 3. MPD alive + library non-empty. Down is NORMAL (on-demand): info, not fail.
    if mpd_vivo; then
        local n
        n="$(mpc listall 2>/dev/null | wc -l)"
        [ "$n" -gt 0 ] \
            && ok "mpd alive, library tracks: $n" \
            || fail "mpd alive but library empty. Fix: check music_directory + mpc update"
    else
        printf '[INFO] mpd is down (normal: on-demand, starts on first pick)\n'
    fi

    # 4. Music dir + font (need config values).
    if [ "$CONFIG_OK" = "1" ]; then
        [ -d "$MUSIC_DIR" ] && [ -n "$(ls -A "$MUSIC_DIR" 2>/dev/null)" ] \
            && ok "music dir non-empty: $MUSIC_DIR" \
            || fail "music dir missing/empty: $MUSIC_DIR. Fix: path in config"
        font_present_cached \
            && ok "font present: $FONT" \
            || warn "font missing: $FONT (falls back; install it or change font)"
    else
        printf '[INFO] music dir + font checks skipped (config invalid)\n'
    fi

    # 5. Binds: installed? conflicts? drift? (needs shortcuts{} values).
    # Fresh-compositor offer lives at the end of this section.
    if [ "$CONFIG_OK" = "0" ]; then
        printf '[INFO] binds checks skipped (config invalid)\n'
    else
    local comp
    comp="$(detect_compositor 2>/dev/null)" || comp=""
    if [ -z "$comp" ]; then
        printf '[INFO] desktop not detected: binds check skipped (run: karui-oto binds [niri|hyprland])\n'
    else
        local file mode combo line
        file="$(comp_file "$comp" 2>/dev/null)"
        if [ "$comp" = "hyprland" ]; then
            printf '[INFO] hyprland syntax: %s (%s)\n' "$(hypr_variant)" "$file"
            if command -v hyprland >/dev/null 2>&1; then
                local _hv _hmaj _mmin _is_lua=0
                _hv="$(hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n 1)"
                _hmaj="${_hv%%.*}"; _mmin="${_hv#*.}"
                { [ "$_hmaj" -ge 1 ] || { [ "$_hmaj" -eq 0 ] && [ "$_mmin" -ge 55 ]; }; } 2>/dev/null && _is_lua=1
                if [ "$_is_lua" = "1" ] && [ "$(hypr_variant)" != "lua" ]; then
                    warn "hyprland $_hv speaks Lua but only legacy hyprland.conf found (binds would fail: run setup/apply to migrate to hyprland.lua)"
                fi
            fi
        fi
        if [ ! -r "$file" ]; then
            printf '[INFO] config file unreadable: %s (binds check skipped)\n' "$file"
            printf 'result: %s ok, %s warnings, %s failures\n' "$SP_OK" "$SP_WARN" "$SP_FAIL" >&2
            [ "$SP_FAIL" -eq 0 ]; return
        fi
            # need binds_conflict from bindsinstall (translators already here)
            local checked=0
            for mode in songs artists albums folders kill; do
                combo="$(shortcut_for "$mode" "$comp")"
                [ -n "$combo" ] || continue
                checked=1
                if line="$(binds_conflict "$comp" "$combo" 2>/dev/null)"; then
                    case "$line" in
                        *karui-oto*|*karui-media*)
                            ok "bind installed: $combo -> $mode ($comp)" ;;
                        *) warn "conflict: $combo already runs: $line -- change shortcuts.* or free it" ;;
                    esac
                else
                    warn "bind missing: $combo not in $comp ($file). Fix: karui-oto binds --apply $comp"
                fi
            done
            [ "$checked" -eq 1 ] \
                || printf '[INFO] no shortcuts assigned (fill shortcuts.* to use binds)\n'
            # Media keys (fixed XF86 table, always installed): warn-only.
            local _mk _found=0
            for _mk in XF86AudioNext XF86AudioPrev XF86AudioPlay; do
                if line="$(binds_conflict "$comp" "$_mk" 2>/dev/null)"; then
                    case "$line" in
                        *karui-*) _found=$((_found + 1)) ;;
                        *) warn "media key pre-bound elsewhere: $_mk -> $line (ours coexists; remove or keep both)" ;;
                    esac
                fi
            done
            [ "$_found" -eq 3 ] \
                && ok "media keys installed: XF86AudioNext/Prev/Play -> karui-media ($comp)" \
                || warn "media keys missing ($_found/3 in $comp). Fix: karui-oto binds --apply $comp"
            # Drift: installed blocks vs shortcuts{} (orphans from emptied or
            # moved combos). The background hook heals this on next picker
            # run; still reported so manual runs can see it. Fix: --sync.
            local _drift
            if _drift="$(binds_drift "$comp" 2>/dev/null)"; then
                ok "binds in sync with shortcuts{} ($comp)"
            else
                warn "binds drift detected ($comp): ${_drift//$'\n'/; } -- fix: karui-oto binds --sync $comp"
            fi
            # Fresh compositor (never installed here): offer the one-time
            # install. Fires only with shortcuts assigned, our markers fully
            # absent, and a writable target file. Default N; piped runs only
            # get the remediation line. This is the single doctor write path
            # (backup + validation inside the flow); everything else is read.
            if [ "$checked" -eq 1 ]; then
                local _has=0 _df
                for _df in $(comp_files_all "$comp"); do
                    if grep -qF -- "$(mark_open "$comp")" "$_df" 2>/dev/null \
                        || grep -qF -- "$(mark_open_rules "$comp")" "$_df" 2>/dev/null; then
                        _has=1; break
                    fi
                done
                if [ "$_has" -eq 0 ] && [ -f "$file" ] && [ -w "$file" ]; then
                    if [ -t 0 ]; then
                        local _ans
                        printf 'No shortcuts assigned to the current compositor (switched compositors?). Install them now? [y/N] ' >&2
                        IFS= read -r _ans
                        case "$_ans" in
                            y|Y|yes|YES)
                                # Consent given: feed it to the flow so it
                                # does not ask twice (stdin may be exhausted).
                                printf 'y\n' | binds_apply_flow "$comp" ;;
                            *) printf '[INFO] skipped: run karui-oto binds --apply %s when ready\n' "$comp" ;;
                        esac
                    else
                        printf '[INFO] no karui blocks in %s: run karui-oto binds --apply %s to install\n' "$file" "$comp"
                    fi
                fi
            fi
    fi
    fi  # end CONFIG_OK=1 binds section; 5b below is config-free

    # 5b. Portal backend sanity (static check, never probed: a hanging probe
    # would stall doctor itself). The gnome portal backend needs GNOME Shell;
    # without it every portal request (kitty startup, GTK file dialogs)
    # stalls ~25s. Nautilus is unaffected by its removal (libportal only).
    if command -v dpkg-query >/dev/null 2>&1 \
        && dpkg-query -W -f='${Status}' xdg-desktop-portal-gnome 2>/dev/null | grep -q "install ok installed"; then
        case "${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-}" in
            *[Gg]nome*) : ;;
            *) warn "xdg-desktop-portal-gnome installed without GNOME Shell: portal requests stall ~25s (slow kitty, stuck file dialogs) -- not a karui-oto bug. Fix: sudo apt remove xdg-desktop-portal-gnome" ;;
        esac
    fi

    # 6. Logo (kitty-only images, universal symbols). Config already passed
    # validate(), so this only reports EFFECTIVE state (foot ignores images,
    # tint without PIL falls back to the original).
    # 6. Logo (needs config values; skipped with INFO when invalid).
    if [ "$CONFIG_OK" = "0" ]; then
        printf '[INFO] logo check skipped (config invalid)\n'
    else
    local _ln="${LOGO_COUNT:-0}" _nsym=0 _nimg=0 _li
    for ((_li = 0; _li < _ln; _li++)); do
        if [ -n "$(eval "printf '%s' \"\${LOGO_${_li}_SYMBOL:-}\"")" ]; then
            _nsym=$((_nsym + 1))
        else
            _nimg=$((_nimg + 1))
        fi
    done
    if [ "$_ln" -eq 0 ]; then
        printf '[INFO] no logo configured (logo[] empty: pickers show no header/logo)\n'
    else
        ok "logo configured: $_nsym symbol(s) + $_nimg image(s)"
        if [ "$_nimg" -ge 1 ] && [ "$TERMINAL" = "foot" ]; then
            warn "logo image ignored on foot (kitty only); symbols still show (or set terminal=kitty)"
        fi
        local _lt _has_tint=0
        for ((_li = 0; _li < _ln; _li++)); do
            _lt="$(eval "printf '%s' \"\${LOGO_${_li}_COLOR:-}\"")"
            # Only image entries carry tint (symbols use ANSI directly).
            if [ -z "$(eval "printf '%s' \"\${LOGO_${_li}_SYMBOL:-}\"")" ] && [ -n "$_lt" ]; then
                _has_tint=1
            fi
        done
        if [ "$_has_tint" = "1" ]; then
            if python3 -c "import PIL.Image" >/dev/null 2>&1; then
                ok "logo tint backend present (python3-pil)"
            else
                warn "no logo tint backend (python3-pil missing: tint ignored, original image used)"
            fi
        fi
    fi
    fi  # end CONFIG_OK=1 logo section

    printf 'result: %s ok, %s warnings, %s failures\n' "$SP_OK" "$SP_WARN" "$SP_FAIL" >&2
    [ "$SP_FAIL" -eq 0 ]
}
