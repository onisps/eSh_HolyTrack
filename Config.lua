-- ============================================================
-- Config: constants and defaults. Shared via ns.
-- ============================================================
local ADDON, ns = ...

ns.SPELL_RENEW = 139          -- Renew
ns.SPELL_POM = 33076          -- Prayer of Mending (cast spell)
ns.SPELL_POM_AURA = 41637     -- Prayer of Mending (aura id on target)
ns.UPDATE_INTERVAL = 0.15     -- seconds between aura scans

-- HandyNotes-style sizing: stored as scale multipliers, real size = base * scale
ns.BASE_W = 200
ns.BASE_H = 18
ns.HEADER_H = 14

ns.defaults = {
    pos = {point = "BOTTOM", relTo = "UIParent", relX = 0, relY = 260},
    width = ns.BASE_W,           -- derived from widthScale (kept for render code)
    rowHeight = ns.BASE_H,       -- derived from heightScale
    widthScale = 1.0,            -- 0.25 .. 2.00, step 0.01 (like HandyNotes icon_scale)
    heightScale = 1.0,
    locked = false,
    showPets = false,
    enabled = true,
    texture = "Interface\\Buttons\\WHITE8X8",
    grow = "up",
    watch = nil, -- created by migration: list of {id, name, enabled, color}
    colors = {
        renew = {0.15, 0.75, 0.35, 1},
        pom = {0.95, 0.85, 0.30, 1},
    },
}

-- Fallback texture list used only if LibSharedMedia-3.0 is unavailable
ns.FALLBACK_TEXTURES = {
    {"Flat (solid)", "Interface\\Buttons\\WHITE8X8"},
    {"Blizzard status bar", "Interface\\TargetingFrame\\UI-StatusBar"},
    {"Glossy", "Interface\\PaperDollInfoFrame\\UI-Character-Statistics-Bar"},
}