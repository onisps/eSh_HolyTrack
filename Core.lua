local ADDON, ns = ...

-- ============================================================
-- Config
-- ============================================================
local SPELL_RENEW = 139          -- Renew
local SPELL_POM = 33076          -- Prayer of Mending (cast spell)
local SPELL_POM_AURA = 41637     -- Prayer of Mending (aura id on target)
local UPDATE_INTERVAL = 0.15

local RENEW_COLOR = {0.15, 0.75, 0.35, 1}
local POM_COLOR = {0.95, 0.85, 0.30, 1}
local ROW_H = 18
local HEADER_H = 14

local defaults = {
    pos = {point = "BOTTOM", relTo = "UIParent", relX = 0, relY = 260},
    width = 200,
    locked = false,
    showPets = false,
    enabled = true,
    rowHeight = 18,
    texture = "Interface\\Buttons\\WHITE8X8",
    grow = "up",
    watch = nil, -- created by migration: list of {id, name, enabled, color}
    colors = {
        renew = {0.15, 0.75, 0.35, 1},
        pom = {0.95, 0.85, 0.30, 1},
    },
}

-- ============================================================
-- Root frame: invisible container. Bars are anchored to its BOTTOM
-- edge and grow upward (DBM style). No background, no border, no title.
-- ============================================================
local frame = CreateFrame("Frame", "eSh_HolyTrackFrame", UIParent)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:SetWidth(200)
frame:SetHeight(400)

-- invisible mover overlay, active only while unlocked
local mover = CreateFrame("Frame", nil, frame)
mover:SetAllPoints()
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover:SetScript("OnDragStart", function()
    if ns.db and not ns.db.locked then frame:StartMoving() end
end)
mover:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    if ns.db then
        local p, _, rt, x, y = frame:GetPoint(1)
        if rt and type(rt) == "table" then rt = rt:GetName() or "UIParent" end
        if rt ~= "UIParent" then rt = "UIParent" end
        ns.db.pos = {point = p, relTo = rt, relX = math.floor(x + 0.5), relY = math.floor(y + 0.5)}
    end
end)
mover:SetScript("OnEnter", function()
    if ns.db and not ns.db.locked then
        GameTooltip:SetOwner(mover, "ANCHOR_RIGHT")
        GameTooltip:SetText("eSh HolyTrack\nDrag to move. /eshht for commands.", 1, 1, 1)
        GameTooltip:Show()
    end
end)
mover:SetScript("OnLeave", GameTooltip_Hide)
mover:Hide() -- shown only while unlocked

-- edit-mode visuals: like Bartender4 config mode
mover.backdrop = mover:CreateTexture(nil, "BACKGROUND")
mover.backdrop:SetAllPoints()
mover.backdrop:SetColorTexture(0, 0, 0, 0.45)
mover.borderL = mover:CreateTexture(nil, "BORDER")
mover.borderL:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
mover.borderL:SetWidth(1)
mover.borderR = mover:CreateTexture(nil, "BORDER")
mover.borderR:SetPoint("TOPRIGHT", mover, "TOPRIGHT", 0, 0)
mover.borderR:SetWidth(1)
mover.borderT = mover:CreateTexture(nil, "BORDER")
mover.borderT:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
mover.borderT:SetHeight(1)
mover.borderB = mover:CreateTexture(nil, "BORDER")
mover.borderB:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT", 0, 0)
mover.borderB:SetHeight(1)
for _, e in ipairs({mover.borderL, mover.borderR, mover.borderT, mover.borderB}) do
    e:SetColorTexture(1, 0.82, 0, 0.9)
end
mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mover.label:SetPoint("CENTER", mover, "CENTER", 0, 0)
mover.label:SetText("Holy Track")
mover.label:SetTextColor(1, 0.82, 0, 1)

-- ============================================================
-- Row / header pools
-- ============================================================
local rows = {}   -- numeric -> StatusBar
local headers = {} -- numeric -> header frame

local function GetRow(i)
        local r = rows[i]
        if not r then
            -- never create frames during combat (secure taint); the pool of 80
            -- pre-created rows is enough for a full raid
            if InCombatLockdown() then return nil end
            r = CreateFrame("StatusBar", "eSh_HolyTrackRow" .. i, frame)
        r:SetHeight((ns.db and ns.db.rowHeight) or ROW_H)
        r:SetMinMaxValues(0, 1)
        r:SetStatusBarTexture((ns.db and ns.db.texture) or "Interface\\Buttons\\WHITE8X8")
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(0, 0, 0, 0.45)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", r, "LEFT", 2, 0)
        r.time = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.time:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        r:SetScript("OnEnter", function(self)
            if self.unit then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetUnitAura(self.unit, self.auraIndex, "HELPFUL")
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        r:EnableMouse(true)
        rows[i] = r
    end
    return r
end

local function GetHeader(i)
    local h = headers[i]
    if not h then
        h = CreateFrame("Frame", nil, frame)
        h:SetHeight(HEADER_H)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        h.text:SetPoint("LEFT", h, "LEFT", 1, 0)
        h:EnableMouse(false)
        headers[i] = h
    end
    return h
end

local function HideAll()
    for _, r in pairs(rows) do r:Hide() end
    for _, h in pairs(headers) do h:Hide() end
end

-- ============================================================
-- Scanning
-- ============================================================
local watched = {} -- map: spellId -> list of entries this scan

local function GetGroupUnits(includePets)
    local units = {}
    if IsInRaid() then
        -- raid1..raidN already includes the player; adding "player" separately
        -- would scan and render your own buffs twice
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
            if includePets then units[#units + 1] = "raidpet" .. i end
        end
    else
        units[#units + 1] = "player"
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
            if includePets then units[#units + 1] = "partypet" .. i end
        end
        if includePets then units[#units + 1] = "pet" end
    end
    return units
end

local function ScanAuras()
    for _, list in pairs(watched) do wipe(list) end
    local units = GetGroupUnits(ns.db.showPets)
    local now = GetTime()

    -- watch maps for this scan (by spell id and by name, since the aura on the
    -- target can carry a different id than the cast spell)
    local watchById, watchByName = {}, {}
    for _, w in ipairs(ns.db.watch) do
        if w.enabled then
            watchById[w.id] = w
            if w.name then watchByName[string.lower(w.name)] = w end
        end
    end

    for _, unit in ipairs(units) do
        if UnitExists(unit) and UnitIsConnected(unit) then
            for i = 1, 40 do
                local name, _, _, count, _, duration, expirationTime, unitCaster, _, _, spellId =
                    UnitAura(unit, i, "HELPFUL")
                if not name then break end

                local w = watchById[spellId]
                if not w and name then
                    w = watchByName[string.lower(name)]
                end
                -- PoM may appear on the target under a different aura id
                if not w and spellId == SPELL_POM_AURA and watchById[SPELL_POM] then
                    w = watchById[SPELL_POM]
                end
                if w and unitCaster == "player" then
                    local timeLeft
                    if expirationTime and expirationTime > 0 then
                        timeLeft = expirationTime - now
                    else
                        timeLeft = (duration and duration > 0 and duration) or 999
                    end
                    if timeLeft > 0 then
                        local list = watched[w.id]
                        if not list then list = {} watched[w.id] = list end
                        local hasExpiry = (expirationTime and expirationTime > 0) or (duration and duration > 0)
                        list[#list + 1] = {
                            name = GetUnitName(unit, true) or unit,
                            unit = unit,
                            index = i,
                            timeLeft = timeLeft,
                            duration = (duration and duration > 0) and duration or 1,
                            stacks = count or 1,
                            noExpiry = not hasExpiry,
                        }
                    end
                end
            end
        end
    end

    for id, list in pairs(watched) do
        if id == SPELL_POM then
            table.sort(list, function(a, b)
                if a.stacks ~= b.stacks then return a.stacks > b.stacks end
                return a.timeLeft < b.timeLeft
            end)
        else
            table.sort(list, function(a, b) return a.timeLeft < b.timeLeft end)
        end
    end
end

-- ============================================================
-- Update: render upward from the bottom edge of the frame.
-- Bottom block: Prayer of Mending rows. Above them: Renew rows.
-- Each block has a small section label on top.
-- ============================================================
local elapsed = 0

local function Update(self, dt)
    if not ns.db then return end
    elapsed = elapsed + dt
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0

    if not ns.db.enabled then
        HideAll()
        return
    end

    ScanAuras()
    HideAll()

    local w = ns.db.width
    local up = ns.db.grow ~= "down"
    local rowIdx, headerIdx = 0, 0
    local y = 0 -- offset from the anchor edge (bottom if growing up, top if growing down)

    local function Place(r, h)
        r:ClearAllPoints()
        if up then
            r:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, y)
            r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, y)
        else
            r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
        end
        r:SetHeight(h)
    end

    local function RenderSection(watch, list, showStacks)
        if #list == 0 then return end
        local color = watch.color or {1, 1, 1, 1}
        -- rows (they hug the anchor edge; header sits on top of the block)
        if not up then
            -- header first when growing down
            headerIdx = headerIdx + 1
            local h = GetHeader(headerIdx)
            Place(h, HEADER_H)
            h.text:SetText(watch.name .. " (" .. #list .. ")")
            h.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            h:Show()
            y = y + HEADER_H + 4
        end
        for _, entry in ipairs(list) do
            rowIdx = rowIdx + 1
            local r = GetRow(rowIdx)
            if r then
            Place(r, ns.db.rowHeight)
            r:SetWidth(w)
            r:SetMinMaxValues(0, entry.duration)
            r:SetValue(entry.timeLeft)
            r:SetStatusBarTexture(ns.db.texture)
            r:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
            r.name:SetText(entry.name)
            if showStacks and entry.stacks and entry.stacks > 1 then
                r.time:SetText("x" .. entry.stacks .. "  " .. (entry.noExpiry and "--" or ("%.1f"):format(entry.timeLeft)))
            else
                r.time:SetText(entry.noExpiry and "--" or ("%.1f"):format(entry.timeLeft))
            end
            r.unit = entry.unit
            r.auraIndex = entry.index
            r:Show()
            y = y + ns.db.rowHeight + 1
            end
        end
        if up then
            -- section label above its rows
            headerIdx = headerIdx + 1
            local h = GetHeader(headerIdx)
            Place(h, HEADER_H)
            h.text:SetText(watch.name .. " (" .. #list .. ")")
            h.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            h:Show()
            y = y + HEADER_H + 4
        end
    end

    -- sections render in watch-list order (per profile)
    for _, watch in ipairs(ns.db.watch) do
        if watch.enabled then
            RenderSection(watch, watched[watch.id] or {}, watch.id == SPELL_POM)
        end
    end
end

frame:SetScript("OnUpdate", Update)

-- ============================================================
-- Init / SavedVariables
-- ============================================================
local VALID_POINTS = {
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
    TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true,
}

local function ApplyDB()
    local db = ns.db
    -- sanitize corrupted saved positions (relTo must be a frame, point a real anchor)
    if type(db.pos) ~= "table" or not VALID_POINTS[db.pos.point] or db.pos.relTo ~= "UIParent" then
        db.pos = {point = "BOTTOM", relTo = "UIParent", relX = 0, relY = 260}
    end
    frame:ClearAllPoints()
    frame:SetPoint(db.pos.point, UIParent, db.pos.point, db.pos.relX, db.pos.relY)
    frame:SetWidth(db.width)
    if db.locked then mover:Hide() else mover:Show() end
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

    local function MergeDefaults(profile)
        for k, v in pairs(defaults) do
            if profile[k] == nil then profile[k] = v end
        end
        if type(profile.pos) ~= "table" then profile.pos = {} end
        for k, v in pairs(defaults.pos) do
            if profile.pos[k] == nil then profile.pos[k] = v end
        end
        if type(profile.colors) ~= "table" then profile.colors = {} end
        for k, v in pairs(defaults.colors) do
            if type(profile.colors[k]) ~= "table" then profile.colors[k] = v end
        end
        if type(profile.texture) ~= "string" then profile.texture = defaults.texture end
        if type(profile.rowHeight) ~= "number" then profile.rowHeight = defaults.rowHeight end
        if type(profile.width) ~= "number" then profile.width = defaults.width end
        if profile.grow ~= "down" then profile.grow = "up" end

        -- Watch list migration: built-ins (Renew / Prayer of Mending) seeded from
        -- the old trackRenew/trackPom toggles and colors.
        if type(profile.watch) ~= "table" then
            profile.watch = {
                {id = SPELL_RENEW, name = "Renew", enabled = profile.trackRenew ~= false, color = profile.colors.renew, builtin = true},
                {id = SPELL_POM, name = "Prayer of Mending", enabled = profile.trackPom ~= false, color = profile.colors.pom, builtin = true},
            }
        end
        for _, w in ipairs(profile.watch) do
            if type(w.color) ~= "table" then w.color = {1, 1, 1, 1} end
            if type(w.enabled) ~= "boolean" then w.enabled = true end
            if type(w.name) ~= "string" or w.name == "" then
                w.name = (GetSpellInfo(w.id or 0)) or ("Spell " .. tostring(w.id or "?"))
            end
        end
    end

    local function SwitchProfile(name)
        if db.profiles[name] then
            MergeDefaults(db.profiles[name])
            db.activeProfile = name
            ns.db = db.profiles[name]
            ApplyDB()
            RefreshAllControls()
        end
    end
    ns.SwitchProfile = SwitchProfile

    MergeDefaults(db.profiles[db.activeProfile])
    ns.db = db.profiles[db.activeProfile]
    ApplyDB()

    -- Pre-create the full row/header pool at login: creating frames inside
    -- OnUpdate during combat taints secure UI (ADDON_ACTION_BLOCKED on
    -- CompactRaidFrame Show/Hide).
    for i = 1, 80 do
        GetRow(i)
        rows[i]:Hide()
    end
    for i = 1, 16 do
        GetHeader(i)
        headers[i]:Hide()
    end

    BuildOptionsPanel()
end)

-- ============================================================
-- Interface Options panel
-- ============================================================
local TEXTURES = {
    {"Flat (solid)", "Interface\\Buttons\\WHITE8X8"},
    {"Blizzard status bar", "Interface\\TargetingFrame\\UI-StatusBar"},
    {"Glossy", "Interface\\PaperDollInfoFrame\\UI-Character-Statistics-Bar"},
}

local panel
local RefreshAllControls -- forward declaration (defined after BuildOptionsPanel)
local function RefreshEverything()
    ApplyDB()
end

local function AddTitle(parent, text, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", size == "big" and "GameFontNormalLarge" or "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function AddCheckbox(parent, label, get, set, anchorTo)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    local txt = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetText(label)
    txt:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked())
    end)
    cb.refresh = function()
        cb:SetChecked(get())
    end
    return cb
end

local function AddSlider(parent, label, min, max, step, get, set, anchorTo)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetWidth(160)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    if not s.text then
        s.text = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s.text:SetPoint("BOTTOM", s, "TOP", 0, 0)
    end
    s.text:SetText(label)
    s.low = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.low:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 6, -6)
    s.low:SetText(min)
    s.high = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.high:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -6, -6)
    s.high:SetText(max)
    s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.value:SetPoint("TOPLEFT", s, "TOPRIGHT", 6, -6)
    s:SetScript("OnValueChanged", function(self, val)
        self.value:SetText(math.floor(val + 0.5))
        set(val)
    end)
    s.refresh = function()
        s:SetValue(get())
        s.value:SetText(math.floor(s:GetValue() + 0.5))
    end
    return s
end

local function OpenColorPicker(colorTable, onDone)
    local r, g, b, a = colorTable[1], colorTable[2], colorTable[3], colorTable[4] or 1
    ColorPickerFrame:SetFrameStrata("TOOLTIP")
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame.hasOpacity = true
    ColorPickerFrame.opacity = a
    ColorPickerFrame.previousValues = {r = r, g = g, b = b, a = a}
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = OpacitySliderFrame:GetValue()
        colorTable[1], colorTable[2], colorTable[3], colorTable[4] = nr, ng, nb, na
        onDone()
    end
    ColorPickerFrame.func = apply
    ColorPickerFrame.opacityFunc = apply
    ColorPickerFrame.cancelFunc = function(prev)
        colorTable[1], colorTable[2], colorTable[3], colorTable[4] = prev.r, prev.g, prev.b, prev.a
        onDone()
    end
    ShowUIPanel(ColorPickerFrame)
end

local function AddColorSwatch(parent, label, colorKey, anchorTo)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(150, 22)
    btn:SetText(label)
    local sw = btn:CreateTexture(nil, "OVERLAY")
    sw:SetSize(16, 16)
    sw:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    sw:SetTexture("Interface\\Buttons\\WHITE8X8")
    local function updateSwatch()
        local c = ns.db.colors[colorKey]
        sw:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
    btn:SetScript("OnClick", function()
        OpenColorPicker(ns.db.colors[colorKey], function()
            updateSwatch()
            RefreshEverything()
        end)
    end)
    btn.refresh = updateSwatch
    return btn
end

function BuildOptionsPanel()
    if panel then return end
    panel = CreateFrame("Frame", "eSh_HolyTrackOptions", InterfaceOptionsFramePanelContainer)
    panel.name = "eSh HolyTrack"
    panel:Hide()

    local title = AddTitle(panel, "eSh HolyTrack", "big")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)

    -- checkboxes (two per row)
    local cb1 = AddCheckbox(panel, "Enable tracking", function() return ns.db.enabled end,
        function(v) ns.db.enabled = v; RefreshEverything() end)
    cb1:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -46)
    local cb2 = AddCheckbox(panel, "Locked (hide drag area)", function() return ns.db.locked end,
        function(v) ns.db.locked = v; RefreshEverything() end)
    cb2:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -46)
    local cb3 = AddCheckbox(panel, "Show pets", function() return ns.db.showPets end,
        function(v) ns.db.showPets = v end)
    cb3:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -74)

    -- sliders
    local sWidth = AddSlider(panel, "Bar width", 80, 600, 10,
        function() return ns.db.width end,
        function(v) ns.db.width = math.floor(v + 0.5); RefreshEverything() end)
    sWidth:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -110)
    local sHeight = AddSlider(panel, "Bar height", 10, 30, 1,
        function() return ns.db.rowHeight end,
        function(v) ns.db.rowHeight = math.floor(v + 0.5); RefreshEverything() end)
    sHeight:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -110)

    -- texture dropdown (LibSharedMedia, like Quartz; falls back to a builtin list)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    local dd = CreateFrame("Frame", "eSh_HolyTrackTextureDD", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, 170)
    UIDropDownMenu_JustifyText(dd, "LEFT")
    local ddLabel = AddTitle(panel, "Bar texture")
    ddLabel:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 8, 0)
    local function textureName(path)
        if LSM then
            for name in pairs(LSM:HashTable("statusbar")) do
                if LSM:Fetch("statusbar", name) == path then return name end
            end
        end
        for _, t in ipairs(TEXTURES) do
            if t[2] == path then return t[1] end
        end
        return path
    end
    local function ddInit(self, level)
        local items = {}
        if LSM then
            for _, name in pairs(LSM:List("statusbar")) do
                items[#items + 1] = {name = name, path = LSM:Fetch("statusbar", name)}
            end
        else
            for _, t in ipairs(TEXTURES) do
                items[#items + 1] = {name = t[1], path = t[2]}
            end
        end
        table.sort(items, function(a, b) return a.name < b.name end)
        for _, t in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = t.name
            info.value = t.path
            info.func = function()
                ns.db.texture = t.path
                UIDropDownMenu_SetSelectedValue(dd, t.path)
                UIDropDownMenu_SetText(dd, t.name)
                RefreshEverything()
            end
            info.checked = ns.db.texture == t.path
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(dd, ddInit)
    UIDropDownMenu_SetSelectedValue(dd, ns.db.texture)
    UIDropDownMenu_SetText(dd, textureName(ns.db.texture))
    dd:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -158)
    dd.refresh = function()
        UIDropDownMenu_SetSelectedValue(dd, ns.db.texture)
        UIDropDownMenu_SetText(dd, textureName(ns.db.texture))
    end

    -- grow direction dropdown
    local growDD = CreateFrame("Frame", "eSh_HolyTrackGrowDD", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(growDD, 170)
    UIDropDownMenu_JustifyText(growDD, "LEFT")
    local growLabel = AddTitle(panel, "Grow direction")
    growLabel:SetPoint("BOTTOMLEFT", growDD, "TOPLEFT", 8, 0)
    local GROWS = {{"Up (bars grow upward)", "up"}, {"Down (bars grow downward)", "down"}}
    UIDropDownMenu_Initialize(growDD, function(self, level)
        for _, g in ipairs(GROWS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = g[1]
            info.value = g[2]
            info.func = function()
                ns.db.grow = g[2]
                UIDropDownMenu_SetSelectedValue(growDD, g[2])
            end
            info.checked = ns.db.grow == g[2]
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(growDD, ns.db.grow)
    growDD:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -158)
    growDD.refresh = function() UIDropDownMenu_SetSelectedValue(growDD, ns.db.grow) end

    -- reset button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 22)
    resetBtn:SetText("Reset position")
    resetBtn:SetScript("OnClick", function()
        ns.db.pos = {point = "BOTTOM", relTo = "UIParent", relX = 0, relY = 260}
        RefreshEverything()
        print("|cff00ff00eSh HolyTrack:|r position reset.")
    end)
    resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 420, -158)

    -- ============================================================
    -- Watch list: what spells to track
    -- ============================================================
    local watchLabel = AddTitle(panel, "Spells to watch", "big")
    watchLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -206)

    -- scroll container
    local scroll = CreateFrame("ScrollFrame", "eSh_HolyTrackWatchScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetSize(560, 160)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -224)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(540, 160)
    scroll:SetScrollChild(scrollChild)

    local watchRows = {}

    local function GetWatchRow(i)
        local r = watchRows[i]
        if not r then
            r = CreateFrame("Frame", nil, scrollChild)
            r:SetSize(520, 24)

            -- enable checkbox
            r.cb = CreateFrame("CheckButton", nil, r, "InterfaceOptionsCheckButtonTemplate")
            r.cb:SetPoint("LEFT", r, "LEFT", 0, 0)
            r.cb:SetHitRectInsets(0, 0, 0, 0)

            -- spell icon
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("LEFT", r.cb, "RIGHT", 6, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- "ID | Name"
            r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)

            -- color swatch (click to change)
            r.sw = CreateFrame("Button", nil, r)
            r.sw:SetSize(18, 18)
            r.sw:SetPoint("RIGHT", r, "RIGHT", -30, 0)
            r.sw.tex = r.sw:CreateTexture(nil, "OVERLAY")
            r.sw.tex:SetAllPoints()
            r.sw.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            r.sw.btex = r.sw:CreateTexture(nil, "BACKGROUND")
            r.sw.btex:SetAllPoints()
            r.sw.btex:SetTexture("Interface\\Buttons\\WHITE8X8")
            r.sw.btex:SetVertexColor(0.2, 0.2, 0.2)

            -- delete (trash) button
            r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
            r.del:SetSize(22, 22)
            r.del:SetPoint("RIGHT", r, "RIGHT", 0, 0)
            r.del:SetText("X")

            watchRows[i] = r
        end
        r:Show()
        return r
    end

    local function RefreshWatchList()
        local watches = ns.db.watch
        for i = #watchRows + 1, #watches do GetWatchRow(i) end
        for i = 1, #watchRows do
            if i <= #watches then
                watchRows[i]:Show()
            else
                watchRows[i]:Hide()
            end
        end
        local y = 0
        for i, w in ipairs(watches) do
            local r = GetWatchRow(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
            y = y + 26

            local name, _, icon = GetSpellInfo(w.id)
            if name then w.name = name end
            r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.label:SetText(w.id .. " | " .. (w.name or "?"))
            r.sw.tex:SetVertexColor(w.color[1], w.color[2], w.color[3], w.color[4] or 1)

            r.cb:SetScript("OnClick", function(self)
                w.enabled = self:GetChecked() and true or false
            end)
            r.cb:SetChecked(w.enabled)

            r.sw:SetScript("OnClick", function()
                OpenColorPicker(w.color, function()
                    r.sw.tex:SetVertexColor(w.color[1], w.color[2], w.color[3], w.color[4] or 1)
                end)
            end)

            r.del:SetScript("OnClick", function()
                for j, other in ipairs(ns.db.watch) do
                    if other == w then
                        table.remove(ns.db.watch, j)
                        break
                    end
                end
                RefreshWatchList()
            end)
        end
        scrollChild:SetHeight(#watches * 26 + 4)
    end
    ns.RefreshWatchList = RefreshWatchList
    panel:SetScript("OnShow", function() RefreshWatchList() end)

    -- add form: [ID input] [Add]  -> fetches name+icon from spell id
    local addLabel = AddTitle(panel, "Add spell by ID:")
    addLabel:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 4, -8)
    local idInput = CreateFrame("EditBox", "eSh_HolyTrackWatchIdBox", panel, "InputBoxTemplate")
    idInput:SetSize(90, 20)
    idInput:SetAutoFocus(false)
    idInput:SetNumeric(true)
    idInput:SetPoint("LEFT", addLabel, "RIGHT", 8, 0)
    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(70, 22)
    addBtn:SetText("Add")
    addBtn:SetPoint("LEFT", idInput, "RIGHT", 8, 0)
    addBtn:SetScript("OnClick", function()
        local id = tonumber(idInput:GetText())
        if not id then
            print("|cff00ff00eSh HolyTrack:|r enter a numeric spell ID.")
            return
        end
        local name = GetSpellInfo(id)
        if not name then
            print("|cff00ff00eSh HolyTrack:|r no spell found with ID " .. id .. " (learn it first or check wowhead).")
            return
        end
        for _, w in ipairs(ns.db.watch) do
            if w.id == id then
                print("|cff00ff00eSh HolyTrack:|r '" .. name .. "' is already in the watch list.")
                return
            end
        end
        -- color: pick from the spell's icon if possible (nice default)
        ns.db.watch[#ns.db.watch + 1] = {id = id, name = name, enabled = true, color = {1, 0.7, 0.2, 1}}
        idInput:SetText("")
        RefreshWatchList()
        print("|cff00ff00eSh HolyTrack:|r now watching '" .. name .. "' (id " .. id .. ").")
    end)

    -- profiles
    local profLabel = AddTitle(panel, "Profiles (settings sets)", "big")
    profLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -428)

    local profDD = CreateFrame("Frame", "eSh_HolyTrackProfileDD", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(profDD, 170)
    UIDropDownMenu_JustifyText(profDD, "LEFT")
    local function profNames()
        local names = {}
        for name in pairs(eSh_HolyTrackDB.profiles) do names[#names + 1] = name end
        table.sort(names)
        return names
    end
    UIDropDownMenu_Initialize(profDD, function(self, level)
        for _, name in ipairs(profNames()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = name
            info.func = function()
                UIDropDownMenu_SetSelectedValue(profDD, name)
                ns.SwitchProfile(name)
                print("|cff00ff00eSh HolyTrack:|r profile switched to '" .. name .. "'.")
            end
            info.checked = eSh_HolyTrackDB.activeProfile == name
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(profDD, eSh_HolyTrackDB.activeProfile)
    profDD:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -448)
    profDD.refresh = function() UIDropDownMenu_SetSelectedValue(profDD, eSh_HolyTrackDB.activeProfile) end

    -- create / delete profile
    local newInput = CreateFrame("EditBox", "eSh_HolyTrackNewProfileBox", panel, "InputBoxTemplate")
    newInput:SetSize(140, 20)
    newInput:SetAutoFocus(false)
    newInput:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -500)
    local createBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    createBtn:SetSize(80, 22)
    createBtn:SetText("Create")
    createBtn:SetPoint("LEFT", newInput, "RIGHT", 10, 0)
    createBtn:SetScript("OnClick", function()
        local name = newInput:GetText()
        if name ~= "" and not eSh_HolyTrackDB.profiles[name] then
            eSh_HolyTrackDB.profiles[name] = {}
            ns.SwitchProfile(name)
            RefreshAllControls()
            newInput:SetText("")
            print("|cff00ff00eSh HolyTrack:|r profile '" .. name .. "' created and activated.")
        elseif eSh_HolyTrackDB.profiles[name] then
            print("|cff00ff00eSh HolyTrack:|r profile '" .. name .. "' already exists.")
        end
    end)
    local deleteBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    deleteBtn:SetSize(80, 22)
    deleteBtn:SetText("Delete")
    deleteBtn:SetPoint("LEFT", createBtn, "RIGHT", 10, 0)
    deleteBtn:SetScript("OnClick", function()
        local name = eSh_HolyTrackDB.activeProfile
        local count = 0
        for _ in pairs(eSh_HolyTrackDB.profiles) do count = count + 1 end
        if count <= 1 then
            print("|cff00ff00eSh HolyTrack:|r cannot delete the last profile.")
            return
        end
        eSh_HolyTrackDB.profiles[name] = nil
        local fallback
        for n in pairs(eSh_HolyTrackDB.profiles) do fallback = n break end
        ns.SwitchProfile(fallback)
        RefreshAllControls()
        print("|cff00ff00eSh HolyTrack:|r profile '" .. name .. "' deleted. Switched to '" .. fallback .. "'.")
    end)

    InterfaceOptions_AddCategory(panel)
end

function RefreshAllControls()
    if not panel then return end
    for _, child in pairs({panel:GetChildren()}) do
        if child.refresh then child.refresh() end
    end
    if ns.RefreshWatchList then ns.RefreshWatchList() end
end

-- ============================================================
-- Slash commands: open the options tab
-- ============================================================
SLASH_ESHHOLYTRACK1 = "/eshht"
SLASH_ESHHOLYTRACK2 = "/holytrack"
SlashCmdList["ESHHOLYTRACK"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "debug" then
        if UnitExists("target") then
            print("|cff00ff00eSh HolyTrack debug:|r buffs on " .. (GetUnitName("target", true) or "target"))
            for i = 1, 40 do
                local name, _, _, count, _, duration, expirationTime, unitCaster, _, _, spellId =
                    UnitAura("target", i, "HELPFUL")
                if not name then break end
                print(("  %s (id %d, stacks %s, caster %s)")
                    :format(name, spellId or 0, tostring(count), tostring(unitCaster)))
            end
        else
            print("|cff00ff00eSh HolyTrack:|r no target for debug")
        end
        return
    end
    -- anything else opens the Interface options tab
    if panel then
        RefreshAllControls()
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel) -- 7.3.5 needs double call
    else
        print("|cff00ff00eSh HolyTrack:|r not initialized yet.")
    end
end
