#!/bin/bash
# ============================================================================
# karui-oto · install.sh — honest installer
# ----------------------------------------------------------------------------
# CONTRACT (read me before running — short on purpose):
#   YES: read-only checks, copy project files to
#        ~/.local/share/karui-oto/, symlink into ~/.local/bin/,
#        create ~/.config/karui-oto/config.jsonc ONLY if missing.
#   NO:  sudo, network, touching existing dotfiles (.bashrc etc.),
#        overwriting your config, touching your MPD. --dry-run first
#        if you like.
# USE:
#   ./install.sh [--dry-run] [--prefix ~/.local] [--force]
#   ./install.sh --help
# UNINSTALL: ./uninstall.sh [--purge] (removes only ours).
# ============================================================================
set -u

PREFIX="${HOME}/.local"
DRYRUN=0
FORCE=0
SRC_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"

usage() {
    sed -n '2,12p' "$SRC_DIR/install.sh" | sed 's/^# \{0,1\}//'
}

log()  { printf 'install: %s\n' "$*"; }
run()  { if [ "$DRYRUN" = "1" ]; then printf '[dry-run] %s\n' "$*"; else eval "$*"; fi; }
# NOTE: eval only with strings built here (own paths), never user input.

fail=0
need() {  # need <command> [note]
    if command -v "$1" >/dev/null 2>&1; then log "ok: $1";
    else printf 'install: MISSING %s %s\n' "$1" "${2:-(required)}" >&2; fail=1; fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRYRUN=1 ;;
        --force) FORCE=1 ;;
        --prefix) PREFIX="$2"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'install: unknown flag: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

log "== 1/3 dependencies (read-only) =="
need bash; need mpc "(Music Player Daemon client)"
need mpd "(the daemon; your current config works)"
need fzf
need python3 "(parses config.jsonc only, stdlib)"
# Terminal: basta UNA de las dos (la eliges con "terminal" en config).
if command -v kitty >/dev/null 2>&1; then log "ok: kitty";
elif command -v foot >/dev/null 2>&1; then log "ok: foot (sin kitty: pon terminal=foot)";
else printf 'install: FALTA kitty o foot (una de las dos)\n' >&2; fail=1; fi
# fzf: features que usamos (--accept-nth, --border-label, --scheme ≈ 2024+)
if command -v fzf >/dev/null 2>&1; then
    fzf --help 2>&1 | grep -q "accept-nth" \
        && log "ok: fzf with --accept-nth" \
        || { log "your fzf is old (no --accept-nth)"; fail=1; }
fi
need setsid "(util-linux; own session for mpDris2)"
if command -v playerctl >/dev/null 2>&1; then log "ok: playerctl (media keys)";
else log "note: no playerctl (only affects karui-media; optional)"; fi
if command -v mpDris2 >/dev/null 2>&1; then log "ok: mpDris2 (MPRIS)";
else log "note: no mpDris2 (set mpris=false in config; optional)"; fi
if [ "$fail" -ne 0 ]; then
    printf 'install: missing required dependencies, aborting unchanged.\n' >&2
    exit 1
fi

SHARE="$PREFIX/share/karui-oto"
BIN="$PREFIX/bin"
CONF="$HOME/.config/karui-oto/config.jsonc"

log "== 2/3 files =="
run "mkdir -p '$SHARE' '$BIN' '$HOME/.config/karui-oto'"
for d in bin lib terminals themes binds; do
    run "cp -a '$SRC_DIR/$d/.' '$SHARE/$d/'"
done
run "cp -a '$SRC_DIR/config.jsonc.example' '$SHARE/'"
run "cp -a '$SRC_DIR/README.md' '$SHARE/'"
run "chmod +x '$SHARE/bin/karui-oto' '$SHARE/bin/karui-media'"
run "ln -sfn '$SHARE/bin/karui-oto' '$BIN/karui-oto'"
run "ln -sfn '$SHARE/bin/karui-media' '$BIN/karui-media'"
if [ -f "$CONF" ] && [ "$FORCE" -ne 1 ]; then
    log "existing config untouched: $CONF (use --force to refresh files)"
else
    run "cp -a '$SRC_DIR/config.jsonc.example' '$CONF'"
fi

log "== 3/3 next steps =="
cat <<EOF
Done.
  1. Review your config: $CONF
  2. Paste the binds (see COMPATIBILITY.txt for your desktop) into
     your compositor, or run: karui-oto setup (assisted, with backup).
  3. If $BIN is not on your PATH:
       export PATH="\$HOME/.local/bin:\$PATH"   # in your .bashrc/.zshrc
Uninstall: ./uninstall.sh [--purge]
EOF
