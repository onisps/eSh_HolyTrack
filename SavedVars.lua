-- ============================================================
-- SavedVars: profile storage, defaults merging/migration, ApplyDB.
-- eSh_HolyTrackDB = { profiles = { name = {...} }, activeProfile = name }
-- ns.db always points at the ACTIVE profile table.
-- ============================================================
local ADDON, ns = ...

local VALID_POINTS = {
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
    TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true,
}

-- Re-position the root frame from the active profile and sync the mover.
function ns.ApplyDB()
    local db = ns.db
    -- sanitize corrupted saved positions (relTo must be a frame, point a real anchor)
    if type(db.pos) ~= "table" or not VALID_POINTS[db.pos.point] or db.pos.relTo ~= "UIParent" then
        db.pos = {point = "BOTTOM", relTo = "UIParent", relX = 0, relY = 260}
    end
    ns.frame:ClearAllPoints()
    ns.frame:SetPoint(db.pos.point, UIParent, db.pos.point, db.pos.relX, db.pos.relY)
    ns.frame:SetWidth(db.width)
    if db.locked then ns.mover:Hide() else ns.mover:Show() end
end

local function MergeDefaults(profile)
    local d = ns.defaults
    for k, v in pairs(d) do
        if profile[k] == nil then profile[k] = v end
    end
    if type(profile.pos) ~= "table" then profile.pos = {} end
    for k, v in pairs(d.pos) do
        if profile.pos[k] == nil then profile.pos[k] = v end
    end
    if type(profile.colors) ~= "table" then profile.colors = {} end
    for k, v in pairs(d.colors) do
        if type(profile.colors[k]) ~= "table" then
            profile.colors[k] = {v[1], v[2], v[3], v[4]} -- deep copy: never share tables
        end
    end
    if type(profile.texture) ~= "string" then profile.texture = d.texture end
    if profile.grow ~= "down" then profile.grow = "up" end

    -- HandyNotes-style scales. Migrate from old absolute px values (200/18).
    if type(profile.widthScale) ~= "number" then
        profile.widthScale = (type(profile.width) == "number" and profile.width > 0)
            and (profile.width / ns.BASE_W) or 1.0
    end
    if type(profile.heightScale) ~= "number" then
        profile.heightScale = (type(profile.rowHeight) == "number" and profile.rowHeight > 0)
            and (profile.rowHeight / ns.BASE_H) or 1.0
    end
    profile.widthScale = math.max(0.25, math.min(2, profile.widthScale))
    profile.heightScale = math.max(0.25, math.min(2, profile.heightScale))
    -- derive effective px sizes from scales (source of truth = scale)
    profile.width = math.floor(ns.BASE_W * profile.widthScale + 0.5)
    profile.rowHeight = math.floor(ns.BASE_H * profile.heightScale + 0.5)

    -- Watch list migration: built-ins (Renew / Prayer of Mending) seeded from
    -- the old trackRenew/trackPom toggles and colors.
    if type(profile.watch) ~= "table" then
        profile.watch = {
            {id = ns.SPELL_RENEW, name = "Renew", enabled = profile.trackRenew ~= false,
                color = {profile.colors.renew[1], profile.colors.renew[2], profile.colors.renew[3], profile.colors.renew[4]}, builtin = true},
            {id = ns.SPELL_POM, name = "Prayer of Mending", enabled = profile.trackPom ~= false,
                color = {profile.colors.pom[1], profile.colors.pom[2], profile.colors.pom[3], profile.colors.pom[4]}, builtin = true},
        }
    end
    for _, w in ipairs(profile.watch) do
        if type(w.color) ~= "table" then w.color = {1, 1, 1, 1} end
        if type(w.enabled) ~= "boolean" then w.enabled = true end
        if type(w.name) ~= "string" or w.name == "" then
            w.name = (GetSpellInfo(w.id or 0)) or ("Spell " .. tostring(w.id or "?"))
        end
        -- id group (e.g. both Rejuvenation ids with Germination) and
        -- per-entry display mode; migrated from the old flat {id=...}
        if type(w.ids) ~= "table" or #w.ids == 0 then
            w.ids = { w.id or 0 }
        end
        w.id = w.ids[1] -- primary id (kept in sync for compat/debug)
        if w.mode ~= "full" and w.mode ~= "rows" and w.mode ~= "summary" then
            w.mode = "full"
        end
    end
end

-- Activate another profile (creates missing settings, re-applies UI).
function ns.SwitchProfile(name)
    local db = eSh_HolyTrackDB
    if db.profiles[name] then
        MergeDefaults(db.profiles[name])
        db.activeProfile = name
        ns.db = db.profiles[name]
        ns.ApplyDB()
        ns.RefreshAllControls()
    end
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
    if not eSh_HolyTrackDB then eSh_HolyTrackDB = {} end
    local db = eSh_HolyTrackDB

    -- Profile structure. Old flat layout (pre-profiles) is migrated into a
    -- profile named after the character so nothing is lost.
    if type(db.profiles) ~= "table" then
        local migrated = {}
        for k, v in pairs(db) do
            if k ~= "profiles" and k ~= "activeProfile" then migrated[k] = v end
        end
        local _, charName = UnitFullName("player")
        local profileName = (charName and charName ~= "") and charName or "Default"
        db.profiles = { [profileName] = migrated }
        db.activeProfile = profileName
    end
    if type(db.activeProfile) ~= "string" or not db.profiles[db.activeProfile] then
        for name in pairs(db.profiles) do
            db.activeProfile = name
            break
        end
    end

    MergeDefaults(db.profiles[db.activeProfile])
    ns.db = db.profiles[db.activeProfile]
    ns.ApplyDB()

    -- Pre-create the full row/header pool at login: creating frames inside
    -- OnUpdate during combat taints secure UI (ADDON_ACTION_BLOCKED on
    -- CompactRaidFrame Show/Hide).
    ns.PreCreatePools()

    ns.BuildOptionsPanel()
end)