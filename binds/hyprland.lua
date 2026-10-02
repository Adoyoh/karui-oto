-- ============================================================================
-- karui-oto · binds/hyprland.lua — append to your hyprland.lua
-- (Hyprland >= 0.55, Lua syntax; for older Hyprland see hyprland.conf)
-- Matches `karui-oto binds hyprland` output on a Lua setup.
-- NOTE: paths are absolute (/home/USUARIO/...): Lua exec_cmd does NOT
-- expand ~, so the tool emits your real $HOME. Replace USUARIO below.
-- Change keys to taste (canonical form: Mod+O, Mod+Shift+P).
-- ============================================================================
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("/home/USUARIO/.local/bin/karui-oto songs"))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("/home/USUARIO/.local/bin/karui-oto artists"))
hl.bind(mainMod .. " + SHIFT" .. " + P", hl.dsp.exec_cmd("/home/USUARIO/.local/bin/karui-oto albums"))
hl.bind(mainMod .. " + SHIFT" .. " + O", hl.dsp.exec_cmd("/home/USUARIO/.local/bin/karui-oto folders"))
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("/home/USUARIO/.local/bin/karui-oto kill"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("/home/USUARIO/.local/bin/karui-media next"), { locked = true, repeating = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("/home/USUARIO/.local/bin/karui-media prev"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("/home/USUARIO/.local/bin/karui-media play-pause"), { locked = true, repeating = true })

-- Floating picker (same TERM_CLASS the tool generates rules for).
-- size takes exact pixels: percent strings are ignored by hl.window_rule.
hl.window_rule({
    name = "karui-oto",
    match = { class = "buscador_mpd" },
    float = true,
    size = { 1200, 700 },
    center = true,
})
