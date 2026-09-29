-- ============================================================
-- Bars: root frame, edit-mode mover, and the row/header frame pools.
-- The root frame is an invisible container; bars anchor to its BOTTOM
-- edge and grow upward (DBM style). All frames are pre-created at login
-- (see PreCreatePools) so nothing is ever created during combat.
-- ============================================================
local ADDON, ns = ...

-- Root frame
ns.frame = CreateFrame("Frame", "eSh_HolyTrackFrame", UIParent)
local frame = ns.frame
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:SetWidth(ns.BASE_W)
frame:SetHeight(400)

-- invisible mover overlay, active only while unlocked
ns.mover = CreateFrame("Frame", nil, frame)
local mover = ns.mover
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

-- Row / header pools
ns.rows = {}    -- numeric -> StatusBar
ns.headers = {} -- numeric -> header frame
local rows, headers = ns.rows, ns.headers

function ns.GetRow(i)
    local r = rows[i]
    if not r then
        -- never create frames during combat (secure taint); the pool of 80
        -- pre-created rows is enough for a full raid
        if InCombatLockdown() then return nil end
        r = CreateFrame("StatusBar", "eSh_HolyTrackRow" .. i, frame)
        r:SetHeight((ns.db and ns.db.rowHeight) or ns.BASE_H)
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
            if self.summaryList then
                -- summary bar: per-target breakdown
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.summaryTitle or "Summary", 1, 1, 1)
                for _, e in ipairs(self.summaryList) do
                    GameTooltip:AddLine(e.name .. ": " .. (e.noExpiry and "--" or ("%.1fs"):format(e.timeLeft)), 0.85, 0.85, 0.85)
                end
                GameTooltip:Show()
            elseif self.unit then
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

function ns.GetHeader(i)
    local h = headers[i]
    if not h then
        h = CreateFrame("Frame", nil, frame)
        h:SetHeight(ns.HEADER_H)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        h.text:SetPoint("LEFT", h, "LEFT", 1, 0)
        h:EnableMouse(false)
        headers[i] = h
    end
    return h
end

function ns.HideAll()
    for _, r in pairs(rows) do r:Hide() end
    for _, h in pairs(headers) do h:Hide() end
end

-- Called once at login: creates every pooled frame up front.
function ns.PreCreatePools()
    for i = 1, 80 do
        ns.GetRow(i)
        rows[i]:Hide()
    end
    for i = 1, 16 do
        ns.GetHeader(i)
        headers[i]:Hide()
    end
end