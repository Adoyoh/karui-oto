#!/usr/bin/env python3
# ============================================================================
# karui-oto · lib/jconfig.py — JSONC -> bash parser (stdlib only)
# ----------------------------------------------------------------------------
# WHAT:
#   Reads config.jsonc and prints bash assignments to stdout for `eval`.
#   Syntax only (comments + JSON); SEMANTICS (ranges, enums, existing
#   paths) are validated by lib/common.sh with clear errors.
#
# WHERE IT FITS:
#   common.sh: eval "$(python3 "$KO_ROOT/lib/jconfig.py" "$CONFIG")".
#   Missing file -> exit 2 (common.sh carries on with defaults). Invalid
#   JSON -> stderr message + exit 1. Hard rules (fatal errors):
#     - "path" maps to MUSIC_DIR ("PATH" uppercased would destroy $PATH!).
#     - Only "icons", "kitty", "foot", "shortcuts" take objects (one
#       level); any other object = error.
#     - Only "hide" takes a scalar array and only "logo" an object array
#       (rest is scalar or error).
#     - Objects -> CLAVE_SUB (e.g. icons.arrow -> ICONS_ARROW).
#     - Scalar arrays -> one var with \x1f separator (bash splits it).
#     - logo[i] -> LOGO_COUNT + LOGO_<i>_<FIELD> scalars.
#     - true/false/null -> "true"/"false"/"" (bash strings).
#   Also prints KO_KEYS='k1 k2...' (top-level keys) so validate() can warn
#   about unknown ones. "modes" never appears in KO_KEYS-driven warnings:
#   common.sh lists it as known; its inner names are checked above.
#
# HOW TO EXTEND:
#   New scalar key: nothing to do here (passes through UPPERCASED, unless
#   it collides with the environment — see KEYMAP). New type: add an
#   explicit rule with a clear error, never guess.
# ============================================================================
import json
import sys

# JSON keys that must NOT be plain-uppercased (environment collision).
KEYMAP = {
    "path": "MUSIC_DIR",
}

# Only these keys take these non-scalar types. "kitty"/"foot"/"shortcuts"
# are sections (same rule as "icons": one level, scalars only). "modes" is
# the single two-level section: mode -> {shuffle,repeat,mpris} scalars only
# (per-mode overrides; empty = inherit the global). It is handled
# explicitly below, never as a generic object.
OBJECT_KEYS = {"icons", "kitty", "foot", "shortcuts"}
# Allowed subkeys per section: typos here used to pass silently (e.g.
# icons.serach kept the default while the user thought it was set).
SECTION_KEYS = {
    "icons": {"search", "arrow", "marker", "album", "folder"},
    "kitty": {"font", "font_size", "width", "height", "color",
              "transparency"},
    "foot": {"font", "font_size", "width", "height", "color",
             "transparency"},
    "shortcuts": {"songs", "artists", "albums", "folders", "kill"},
}
ARRAY_KEYS = {"hide"}
MODES_ALLOWED_MODES = {"songs", "artists", "albums", "folders"}
MODES_ALLOWED_KEYS = {"shuffle", "repeat", "mpris"}
# Logo items: exactly one of symbol/image plus optional knobs each.
# gif is rejected with guidance (animated images unsupported by design).
LOGO_ALLOWED_KEYS = {"symbol", "image", "gif", "color", "size", "position",
                     "transparency"}
SEP = "\x1f"


def strip_comments(src):
    """Strip // and /* */ outside strings. Minimal state machine (~20 lines).
    Inside strings (with their \" escapes) nothing is touched: URLs and
    values containing // survive. No dependencies: on purpose, so the whole
    thing stays auditable.
    """
    out = []
    i, n = 0, len(src)
    in_str = False
    while i < n:
        c = src[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(src[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def shquote(value):
    """Escape a string for safe bash eval: ' -> '\''."""
    return "'" + str(value).replace("'", "'\\''") + "'"


def emit(name, value):
    if value is None:
        print(f"{name}={shquote('')}")
    elif isinstance(value, bool):
        print(f"{name}={shquote(str(value).lower())}")
    else:
        print(f"{name}={shquote(value)}")


def main():
    if len(sys.argv) != 2:
        print("usage: jconfig.py <config.jsonc>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except FileNotFoundError:
        return 2  # no file: caller carries on with defaults
    except OSError as exc:
        print(f"jconfig: cannot read {path}: {exc}", file=sys.stderr)
        return 1
    try:
        data = json.loads(strip_comments(raw))
    except json.JSONDecodeError as exc:
        print(f"jconfig: invalid JSON in {path}: {exc}", file=sys.stderr)
        return 1
    if not isinstance(data, dict):
        print(f"jconfig: root must be an object {{...}} in {path}",
              file=sys.stderr)
        return 1
    print(f"KO_KEYS={shquote(' '.join(data.keys()))}")
    for key, value in data.items():
        # modes: two-level section (mode -> knob -> scalar). Validated here
        # structurally (names); value semantics (true/false/empty) are
        # validated by lib/common.sh with clear errors.
        if key == "modes":
            if not isinstance(value, dict):
                print(f"jconfig: 'modes' must be an object in {path}",
                      file=sys.stderr)
                return 1
            for mode, mval in value.items():
                if mode not in MODES_ALLOWED_MODES:
                    print(f"jconfig: unknown mode 'modes.{mode}' in {path} "
                          f"(valid: {sorted(MODES_ALLOWED_MODES)})",
                          file=sys.stderr)
                    return 1
                if not isinstance(mval, dict):
                    print(f"jconfig: 'modes.{mode}' must be an object "
                          f"in {path}", file=sys.stderr)
                    return 1
                for sub, subval in mval.items():
                    if sub not in MODES_ALLOWED_KEYS:
                        print(f"jconfig: unknown key 'modes.{mode}.{sub}' "
                              f"in {path} (valid: {sorted(MODES_ALLOWED_KEYS)})",
                              file=sys.stderr)
                        return 1
                    if isinstance(subval, (dict, list)):
                        print(f"jconfig: 'modes.{mode}.{sub}' must be scalar "
                              f"in {path}", file=sys.stderr)
                        return 1
                    emit(f"MODES_{mode.upper()}_{sub.upper()}", subval)
            continue
        # logo: array of objects (the only array-of-objects section).
        # Emits LOGO_COUNT + LOGO_<i>_<FIELD> scalars; value semantics
        # (ranges, files, vocab) are validated by lib/common.sh.
        if key == "logo":
            if not isinstance(value, list):
                print(f"jconfig: 'logo' must be an array in {path}",
                      file=sys.stderr)
                return 1
            print(f"LOGO_COUNT={shquote(str(len(value)))}")
            for i, item in enumerate(value):
                if not isinstance(item, dict):
                    print(f"jconfig: 'logo[{i}]' must be an object in {path}",
                          file=sys.stderr)
                    return 1
                for sub in item.keys():
                    if sub not in LOGO_ALLOWED_KEYS:
                        print(f"jconfig: unknown key 'logo[{i}].{sub}' "
                              f"in {path} (valid: {sorted(LOGO_ALLOWED_KEYS)})",
                              file=sys.stderr)
                        return 1
                if "gif" in item:
                    print(f"jconfig: 'logo[{i}].gif' unsupported in {path}: "
                          f"animated images are not supported, "
                          f"use a PNG frame as image", file=sys.stderr)
                    return 1
                has_sym = "symbol" in item
                has_img = "image" in item
                if has_sym == has_img:
                    print(f"jconfig: 'logo[{i}]' needs exactly one of "
                          f"'symbol'/'image' in {path}", file=sys.stderr)
                    return 1
                for sub, subval in item.items():
                    if isinstance(subval, (dict, list)):
                        print(f"jconfig: 'logo[{i}].{sub}' must be scalar "
                              f"in {path}", file=sys.stderr)
                        return 1
                    emit(f"LOGO_{i}_{sub.upper()}", subval)
            continue
        name = KEYMAP.get(key, key.upper())
        if isinstance(value, dict):
            if key not in OBJECT_KEYS:
                print(f"jconfig: '{key}' takes no object in {path} "
                      f"(only {sorted(OBJECT_KEYS)})", file=sys.stderr)
                return 1
            for sub, subval in value.items():
                if sub not in SECTION_KEYS[key]:
                    print(f"jconfig: unknown key '{key}.{sub}' in {path} "
                          f"(valid: {sorted(SECTION_KEYS[key])})",
                          file=sys.stderr)
                    return 1
                if isinstance(subval, (dict, list)):
                    print(f"jconfig: '{key}.{sub}' must be scalar in {path}",
                          file=sys.stderr)
                    return 1
                emit(f"{name}_{sub.upper()}", subval)
        elif isinstance(value, list):
            if key not in ARRAY_KEYS:
                print(f"jconfig: '{key}' takes no array in {path} "
                      f"(only {sorted(ARRAY_KEYS)})", file=sys.stderr)
                return 1
            for item in value:
                if isinstance(item, (dict, list)):
                    print(f"jconfig: items of '{key}' must be scalar "
                          f"in {path}", file=sys.stderr)
                    return 1
            emit(name, SEP.join("" if v is None else str(v).lower()
                                if isinstance(v, bool) else str(v)
                                for v in value))
        else:
            emit(name, value)
    return 0


if __name__ == "__main__":
    sys.exit(main())
