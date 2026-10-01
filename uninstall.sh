#!/bin/bash
# ============================================================================
# karui-oto · uninstall.sh — removes ONLY ours (binaries, share, our binds)
# USE: ./uninstall.sh [--purge] [comp]
#   no flags: binaries + share + our compositor binds. Your config
#             (~/.config/karui-oto/) STAYS.
#   --purge:  config too. Your MPD and music are NEVER touched.
#   [comp]:   clean only that desktop (niri hyprland sway i3 gnome kde
#             xfce cinnamon mate openbox bspwm). Default: the detected
#             desktop plus any other config file holding our marked block.
# Binds cleanup only deletes OUR marked block / karui-oto entries
# (backup first in ~/.config/karui-oto/backups/); your own binds stay.
# ============================================================================
set -u

SRC_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
export KO_ROOT="$SRC_DIR"
source "$KO_ROOT/lib/common.sh"
source "$KO_ROOT/lib/binds.sh"
source "$KO_ROOT/lib/bindsinstall.sh"

PURGE=0
ONLY=""
for a in "$@"; do
    case "$a" in
        --purge) PURGE=1 ;;
        niri|hyprland|sway|i3|gnome|kde|xfce|cinnamon|mate|openbox|bspwm) ONLY="$a" ;;
        --help|-h) sed -n '2,12p' "$SRC_DIR/uninstall.sh" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'uninstall: unknown argument: %s\n' "$a" >&2; exit 1 ;;
    esac
done

clean_file_comp() {  # <comp>: remove our marked block if present (backup first)
    local comp="$1" file bak
    file="$(comp_file "$comp")"
    [ -f "$file" ] || return 0
    grep -qF "$(mark_open "$comp")" "$file" || return 0
    if managed_file "$file"; then
        printf 'uninstall: skip %s (home-manager managed, remove the snippet from your nix config)\n' "$file"
        return 0
    fi
    bak="$(backup_file "$file")"
    remove_block "$comp" "$file"
    printf 'uninstall: removed our binds from %s (backup: %s)\n' "$file" "$bak"
    if [ "$comp" = "niri" ] && command -v niri >/dev/null 2>&1; then
        niri validate >/dev/null 2>&1 || {
            cp -a "$bak" "$file"
            printf 'uninstall: niri validate FAILED — restored backup, binds kept\n' >&2
        }
    fi
}

clean_live_comp() {  # <comp>: remove our karui-oto entries from the live store
    local comp="$1" bak found=0
    case "$comp" in
        gnome|cinnamon|mate)
            command -v gsettings >/dev/null 2>&1 || return 0
            if gsettings get "$(de_gsettings_schema "$comp")" custom-keybindings 2>/dev/null | grep -q "karui-oto"; then
                found=1
            fi ;;
        kde)
            grep -q "karui-" "${XDG_CONFIG_HOME:-$HOME/.config}/kglobalaccelrc" 2>/dev/null && found=1 ;;
        xfce)
            command -v xfconf-query >/dev/null 2>&1 || return 0
            if xfconf-query -c xfce4-keyboard-shortcuts -l -v 2>/dev/null | grep -q "karui-"; then
                found=1
            fi ;;
        *) return 0 ;;
    esac
    [ "$found" = "1" ] || return 0
    bak="$(backup_settings "$comp")"
    remove_block "$comp" ""
    printf 'uninstall: removed our shortcuts from %s (backup: %s)\n' "$comp" "$bak"
}

clean_binds() {
    local comp="$1" c
    if [ -n "$comp" ]; then
        if comp_is_file "$comp"; then clean_file_comp "$comp";
        else clean_live_comp "$comp"; fi
        return 0
    fi
    # Default: detected desktop first (covers live stores), then sweep any
    # other text config still holding our marked block.
    comp="$(detect_compositor 2>/dev/null)" || comp=""
    if [ -n "$comp" ]; then
        if comp_is_file "$comp"; then clean_file_comp "$comp";
        else clean_live_comp "$comp"; fi
    fi
    for c in niri hyprland sway i3 openbox bspwm; do
        [ "$c" = "$comp" ] && continue
        clean_file_comp "$c"
    done
    if [ -z "$comp" ]; then
        printf 'uninstall: desktop not detected, swept text configs for our marked block\n'
    fi
}

SHARE="$HOME/.local/share/karui-oto"
for f in "$HOME/.local/bin/karui-oto" "$HOME/.local/bin/karui-media"; do
    if [ -L "$f" ] || [ -f "$f" ]; then rm -f "$f" && echo "gone: $f"; fi
done
[ -d "$SHARE" ] && rm -rf "$SHARE" && echo "gone: $SHARE"
clean_binds "$ONLY"
if [ "$PURGE" = "1" ]; then
    rm -rf "$HOME/.config/karui-oto" && echo "gone: ~/.config/karui-oto (purge)"
else
    echo "kept: ~/.config/karui-oto/ (--purge to remove)"
fi
echo "done."
