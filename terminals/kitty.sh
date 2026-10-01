#!/bin/bash
# ============================================================================
# karui-oto · terminals/kitty.sh — kitty adapter
# ----------------------------------------------------------------------------
# WHAT:
#   Translates "open picker" into kitty flags. The only public function is
#   term_open(): takes the picker command and launches it in a small
#   floating window with the config aesthetics.
#
# WHERE IT FITS:
#   bin/karui-oto sources it when TERMINAL=kitty and calls term_open.
# Consumed vars (all from config): TERM_CLASS, WIDTH/HEIGHT ("95c" form),
# WIN_PAD, FONT/SIZE, TRANSPARENCY_KITTY, KITTY_LOGO_OPTS (window_logo_*,
# empty when the logo[] section has no image: symbols need no flags).
#
# HOW TO EXTEND (new terminal, e.g. terminals/wezterm.sh):
#   1) Copy this file. 2) Implement term_open() with the equivalent flags
#      (app-id for compositor rules, size in cells, padding, font, opacity).
#      3) Add the name to validate()'s case in lib/common.sh. KO_DRYRUN=1
#      echoes instead of exec (tests).
# ============================================================================

# term_open <command...>: opens <command> in the picker window.
# Never returns (exec), except KO_DRYRUN=1 (prints, returns 0 for tests).
# `color` (T_BG/T_FG computed in common.sh) paints bg+text of THIS window;
# empty = your kitty global theme (historic behavior).
term_open() {
    local args=(--class="$TERM_CLASS"
        -o "initial_window_width=${WIDTH}c"
        -o "initial_window_height=${HEIGHT}c"
        -o "window_padding_width=$WIN_PAD"
        -o "font_family=$FONT"
        -o "font_size=$FONT_SIZE"
        -o "background_opacity=$TRANSPARENCY_KITTY")
    if [ -n "${T_BG:-}" ]; then
        args+=(-o "background=$T_BG" -o "foreground=$T_FG")
    fi
    # Logo image (kitty only): window logo in the corner over the picker.
    # (:- guard: load_config always fills it, but term_open stays safe alone.)
    if [ -n "${KITTY_LOGO_OPTS[*]:-}" ]; then
        args+=("${KITTY_LOGO_OPTS[@]}")
    fi
    if [ "${KO_DRYRUN:-0}" = "1" ]; then
        printf 'kitty'; printf ' %q' "${args[@]}" -e "$@"
        printf '\n'
        return 0
    fi
    # shellcheck disable=SC2093 # -e ... & + disown on purpose (non-blocking)
    # Redirections: the child must NOT inherit the caller's stdout/stderr.
    # Without this, launching from a script/terminal hangs the parent until
    # the window closes (the grandchild keeps the pipe open).
    kitty "${args[@]}" -e "$@" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null
}
