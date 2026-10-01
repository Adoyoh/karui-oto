#!/bin/bash
# ============================================================================
# karui-oto · lib/picker.sh
# ----------------------------------------------------------------------------
# WHAT:
#   List building and fzf dialogs + MPD queue assembly per mode:
#   songs (tags), artists (folders), albums (grouped tags).
#
# WHERE IT FITS:
#   bin/karui-oto calls run_pick <mode>: opens fzf, builds the queue and
#   plays. Colors come from the theme (themes/), icons from the `icons`
#   config section, and behavior (shuffle/repeat/mpris) also from config.
#   This file never opens terminals (that's terminals/) nor decides
#   shortcuts (that's the compositor).
#
# HOW TO EXTEND (new mode, e.g. "genres"):
#   1) list_genres() printing "display \t hidden" (display = shown and
#      matched; hidden = what comes back with --accept-nth).
#   2) queue_genres() reading the selection and building the queue with mpc.
#   3) pick() + run_pick(): add the case + border-label/prompt (new LBL_/PRM_).
#   4) bin/karui-oto: add the subcommand + binds/ + README.
#   Golden rule: fzf displays, mpc executes; never mix.
#
# DOCUMENTED QUIRKS (don't "fix" without reading this):
#   - `mpc playlist` prints "Artist - Title", NOT paths: never locate
#     tracks with grep over playlist. An insert's position is assumed
#     AT THE END (verified 3x on mpd 0.24/mpc 0.24; the man says otherwise).
#   - `mpc listall -f` IGNORES the format (prints bare paths): the tagged
#     list comes from `mpc search -f ... title ""` (matches all, ~0.3s).
#   - `%artist%` in -f shows only the FIRST value of multi-value tags.
#   - Bare `mpc play` with random on starts at random: always `play <N>`.
# ============================================================================

# --- Config icons -> display vars ------------------------------------------------
# The `icons` jsonc section rules (user deletes/pastes any nerd font).
# No ICONS knob: without Nerd Fonts, put ascii in by hand.
# (Note: fzf accepts empty prompt/pointer; the trailing space is cosmetic.)
PTR="${ICONS_ARROW} "
PRM_SONGS="${ICONS_SEARCH} "
PRM_ARTISTS="${ICONS_SEARCH} artista › "
PRM_ALBUMS="${ICONS_SEARCH} álbum › "
PRM_FOLDERS="${ICONS_SEARCH} carpeta › "
MRK="${ICONS_MARKER} "
LBL_SONGS=" canción "
LBL_ARTISTS=" ${ICONS_ALBUM} artista "
LBL_ALBUMS=" ${ICONS_ALBUM} álbum "
LBL_FOLDERS=" carpeta "

# --- Shared fzf flags ------------------------------------------------------------
# Fills the global FZF_FLAGS array (array = no quoting pain with spaces or
# the TAB in -d). Usage:
#   fzf_base; list_songs | fzf "${FZF_FLAGS[@]}" --prompt=... --border=...
# LOGO_HEADER (logo[].symbol entries, empty when no symbols) rides here so
# all four pickers show it with zero per-mode code.
fzf_base() {
    # NOTE: no -d/--with-nth/--accept-nth on purpose: only modes with a
    # hidden TAB field (songs, albums) add them. In artists (no TAB) those
    # flags would return empty.
    FZF_FLAGS=(--ansi
        --layout=reverse --height=100% --cycle --scroll-off=4
        --highlight-line --info=inline-right --color="$FZF_COLOR")
    [ -n "${LOGO_HEADER:-}" ] && FZF_FLAGS+=(--header="$LOGO_HEADER")
}

# --- SONGS MODE ------------------------------------------------------------------
# Source: real tags (`title ""` = everything). Display "artist · album · title";
# hidden after TAB: real path. Falls back to path when tags are missing.
list_songs() {
    mpc search -f $'%file%\t%artist%\t%album%\t%title%' title "" 2>/dev/null \
    | awk -F'\t' -v A_ART="$C_ARTIST" -v A_ALB="$C_ALBUM" \
                 -v A_TRK="$C_TRACK" -v A_SEP="$C_SEP" -v A_RS="$C_RESET" \
                 -v SEP="$C_SEP_TXT" '{
        real=$1; artist=$2; album=$3; title=$4
        if (real == "") next
        n=split(real, pp, "/")
        if (artist == "") artist=(n >= 1 ? pp[1] : "?")
        if (album == "") album=(n >= 2 ? pp[2] : "?")
        if (title == "") {
            title=pp[n]
            sub(/\.(flac|mp3|ogg|m4a|opus|wav|aac)$/, "", title)
            gsub(/_/, " ", title)
        }
        printf "%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\t%s\n", \
            A_ART, artist, A_RS, A_SEP, SEP, A_RS, \
            A_ALB, album, A_RS, A_SEP, SEP, A_RS, \
            A_TRK, title, A_RS, real
    }'
}

# --- ARTISTS MODE -------------------------------------------------------------------
# Source: ARTIST/ALBUMARTIST tags (+ conservative feat-split, + min_tracks).
# Rationale: folders only fit tidy libraries; tags fit everyone (singles in
# one folder, loose files). Tidy users keep the `folders` bind instead.
#
# split_feats (below): "X feat. Y" -> X AND Y (both list the collab), but
# ONLY on explicit markers with non-letter borders (feat.?|ft.?|featuring
# |x|with, case-insensitive). NEVER on & , / y and — those are band names
# (AC/DC, Earth Wind & Fire, Daryl Hall & John Oates, Bill Withers...).
# Counts come from ONE full scan (fast); multi-value 2nd artists may
# undercount slightly (documented, harmless: pure guests hide, findable
# via songs mode or their host's queue).
split_feats() {
    awk '{
        line = $0
        low = tolower(line)
        marked = ""
        rest = line; rlow = low
        sep = sprintf("%c", 30)
        # Walk marker matches, cutting pieces around them.
        while (match(rlow, /(^|[^a-z0-9])(feat\.?|ft\.?|featuring|x|with)([^a-z0-9]|$)/)) {
            pre = substr(rest, 1, RSTART - 1)
            marked = marked pre sep
            rest = substr(rest, RSTART + RLENGTH)
            rlow = substr(rlow, RSTART + RLENGTH)
        }
        marked = marked rest
        n = split(marked, parts, sep)
        for (i = 1; i <= n; i++) {
            p = parts[i]
            gsub(/^ +| +$/, "", p)
            if (p == "") continue
            lp = tolower(p)
            if (lp ~ /^(feat\.?|ft\.?|featuring|x|with)$/) continue
            print p
        }
    }'
}

list_artists() {
    local counts hide_awk
    counts="$(mktemp)"
    # Doubling backslashes: awk string parsing would degrade "\." to "."
    # and over-match (same trap as folders mode — see there).
    hide_awk="${HIDE_RE//\\/\\\\}"
    mpc search -f "%artist%\t%albumartist%" title "" 2>/dev/null \
    | awk -F'\t' '{ if ($1 != "") c[$1]++; if ($2 != "") c[$2]++ }
                   END { for (k in c) printf "%s\t%d\n", k, c[k] }' \
    | sort > "$counts"
    {
        mpc list artist 2>/dev/null
        mpc list albumartist 2>/dev/null
        mpc list artist 2>/dev/null | split_feats
    } | sort -u \
      | awk -F'\t' -v min="${MIN_TRACKS:-1}" -v hide="$hide_awk" '
        NR==FNR { cnt[$1]=$2; next }
        {
            n = ($1 in cnt) ? cnt[$1] : 0
            if (n + 0 < min + 0) next
            if (hide != "" && $0 ~ ("^(" hide ")$")) next
            print
        }' "$counts" -
    rm -f "$counts"
}

# --- FOLDERS MODE -----------------------------------------------------------------
# Source: EVERY folder under MUSIC_DIR as relative path (artists AND
# albums: "Ado/[2024] Zanmu"). Same queue semantics as artists (whole
# subtree shuffled). HIDE_RE applies to the first component; any hidden
# segment ("/.") excludes the path.
list_folders() {
    # NOTE: HIDE_RE backslashes are doubled for awk string parsing (else
    # "\." degrades to "." and would over-match). grep-based lists don't
    # need this; only this awk path does.
    local HIDE_AWK="${HIDE_RE//\\/\\\\}"
    find "$MUSIC_DIR" -mindepth 1 -type d -printf '%P\n' 2>/dev/null \
        | grep -vE '(^|/)\.' \
        | { if [ -n "$HIDE_AWK" ]; then
                awk -v re="^(${HIDE_AWK})$" -F/ '{ if ($1 !~ re) print }'
            else cat; fi; } \
        | sort
}

# --- ALBUMS MODE ------------------------------------------------------------------
# Source: tags (`list album group artist`: unindented artist + 4-space
# albums; falls back to plain `list album` if MPD lacks group support).
# Display "Artist — Album"; hidden after TAB: artist+album joined (that
# joiner never occurs in real names). Queue uses exact find on BOTH tags
# so the 15 "Greatest Hits" by different artists never mix.
list_albums() {
    if mpc list album group artist >/dev/null 2>&1; then
        mpc list album group artist 2>/dev/null | awk '{
            if ($0 ~ /^$/) { artist=""; next }
            if ($0 ~ /^    /) {
                album=$0; sub(/^    /, "", album)
                if (artist != "")
                    printf "%s — %s\t%s\x1f%s\n", artist, album, artist, album
                next
            }
            artist=$0
        }'
    else
        # Fallback without group: display = album; hidden = "SEP+album".
        mpc list album 2>/dev/null | sort -u \
            | awk '{ printf "%s\t\x1f%s\n", $0, $0 }'
    fi
}

# --- Per-mode fzf dialogs (print the SELECTION to stdout) ------------------------
pick_songs() {
    fzf_base
    list_songs | fzf "${FZF_FLAGS[@]}" \
        -d $'\t' --with-nth=1 --accept-nth=2 --scheme=path \
        --prompt="$PRM_SONGS" --pointer="$PTR" --marker="$MRK" \
        --border=rounded --border-label="$LBL_SONGS" --border-label-pos=3
}

pick_artists() {
    fzf_base
    list_artists | fzf "${FZF_FLAGS[@]}" \
        --prompt="$PRM_ARTISTS" --pointer="$PTR" --marker="$MRK" \
        --border=rounded --border-label="$LBL_ARTISTS" --border-label-pos=3 \
        --list-label=" $(list_artists | wc -l) " --list-label-pos=3
}

pick_folders() {
    fzf_base
    list_folders | fzf "${FZF_FLAGS[@]}" \
        --prompt="$PRM_FOLDERS" --pointer="$PTR" --marker="$MRK" \
        --border=rounded --border-label="$LBL_FOLDERS" --border-label-pos=3 \
        --list-label=" $(list_folders | wc -l) " --list-label-pos=3
}

pick_albums() {
    fzf_base
    list_albums | fzf "${FZF_FLAGS[@]}" \
        -d $'\t' --with-nth=1 --accept-nth=2 \
        --prompt="$PRM_ALBUMS" --pointer="$PTR" --marker="$MRK" \
        --border=rounded --border-label="$LBL_ALBUMS" --border-label-pos=3 \
        --list-label=" $(list_albums | wc -l) " --list-label-pos=3
}

# --- Per-mode MPD queues ------------------------------------------------------------
# queue_songs: whole library (picked first + rest shuffled unless
# SHUFFLE=false) and explicit `play 1` (bare play with random on starts
# at random on mpd 0.24). queue_artists/albums: clear + exact content.
queue_songs() {
    local sel="$1"
    mpc clear >/dev/null 2>&1
    mpc add "$sel" >/dev/null 2>&1
    if [ "$SHUFFLE" = "true" ]; then
        mpc listall 2>/dev/null | grep -vF "$sel" | shuf | mpc add >/dev/null 2>&1
    else
        mpc listall 2>/dev/null | grep -vF "$sel" | mpc add >/dev/null 2>&1
    fi
    mpc play 1 >/dev/null 2>&1
    apply_modes
}

queue_artists() {
    local sel="$1" esc re_b re_f
    # Exact matches first (multi-value tags included: ARTIST=A;B matches A).
    # Then single-string feats ("X feat. A") and title feats ("(feat. A)")
    # via word-boundary filter: "Ado" never eats "Shadow" (verified).
    # Covers are NOT feats (title without feat context is excluded).
    esc="$(printf '%s' "$sel" | sed 's/[^A-Za-z0-9_]/\\&/g')"
    re_b="(?<![A-Za-z0-9])${esc}(?![A-Za-z0-9])"
    re_f="(feat(\.|uring)?|ft\.?|with|&|×| x |duet|vs\.?|versus)"
    mpc clear >/dev/null 2>&1
    {
        mpc find albumartist "$sel"
        mpc find artist "$sel"
        {
            mpc search -f $'%file%\t%artist%\t%albumartist%\t%title%' artist "$sel"
            mpc search -f $'%file%\t%artist%\t%albumartist%\t%title%' albumartist "$sel"
            mpc search -f $'%file%\t%artist%\t%albumartist%\t%title%' title "$sel"
        } | sort -u | while IFS=$'\t' read -r archivo art albart titulo; do
            if printf '%s\n%s\n' "$art" "$albart" | grep -Pqi "$re_b"; then
                printf '%s\n' "$archivo"
            elif printf '%s' "$titulo" | grep -Pqi "$re_f" \
              && printf '%s' "$titulo" | grep -Pqi "$re_b"; then
                printf '%s\n' "$archivo"
            fi
        done
    } | sort -u | { if [ "$SHUFFLE" = "true" ]; then shuf; else cat; fi; } | mpc add >/dev/null 2>&1 || return 1
    apply_modes
    mpc play >/dev/null 2>&1
}

# queue_folders: identical to artists (any subtree, not just top level).
queue_folders() {
    local sel="$1"
    mpc clear >/dev/null 2>&1
    mpc update --wait "$sel" >/dev/null 2>&1
    mpc add "$sel" >/dev/null 2>&1 || return 1
    apply_modes
    mpc play >/dev/null 2>&1
}

queue_albums() {
    local sel="$1" artista album
    artista="${sel%%$'\x1f'*}"
    album="${sel#*$'\x1f'}"
    mpc clear >/dev/null 2>&1
    if [ -n "$artista" ]; then
        mpc find album "$album" artist "$artista" | mpc add >/dev/null 2>&1
    else
        mpc find album "$album" | mpc add >/dev/null 2>&1
    fi
    apply_modes
    mpc play >/dev/null 2>&1
}

# --- Pick orchestration: fzf -> queue -> play -> MPRIS --------------------------------
# Empty (Esc/Ctrl-C): just closes if music plays or the queue is non-empty;
# otherwise kills everything so no idle daemon is left behind. On exit the
# terminal closes itself (kitty close_on_child_death / foot exits with child).
run_pick() {
    local modo="$1" sel=""
    # Effective behavior for THIS mode: modes.<modo>.* overrides win,
    # globals from setup stay otherwise (queue/apply_modes/mpris see it).
    apply_mode_overrides "$modo"
    case "$modo" in
        songs)   sel="$(pick_songs)" ;;
        artists) sel="$(pick_artists)" ;;
        albums)  sel="$(pick_albums)" ;;
        folders) sel="$(pick_folders)" ;;
        *) die "unknown internal mode: $modo" ;;
    esac
    if [ -z "$sel" ]; then
        hay_musica && exit 0
        kill_all; exit 0
    fi
    "queue_$modo" "$sel" || { kill_all; exit 1; }
    launch_mpris
}

