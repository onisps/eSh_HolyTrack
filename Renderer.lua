-- ============================================================
-- Renderer: the OnUpdate loop. Scans auras and lays out the bars
-- from the frame's anchor edge (bottom if growing up, top if growing
-- down), one section per enabled watch-list entry, each with a label.
-- ============================================================
local ADDON, ns = ...

local elapsed = 0

local function Update(self, dt)
    if not ns.db then return end
    elapsed = elapsed + dt
    if elapsed < ns.UPDATE_INTERVAL then return end
    elapsed = 0

    if not ns.db.enabled then
        ns.HideAll()
        return
    end

    ns.ScanAuras()
    ns.HideAll()

    local w = ns.db.width
    local up = ns.db.grow ~= "down"
    local rowIdx, headerIdx = 0, 0
    local y = 0 -- offset from the anchor edge (bottom if growing up, top if growing down)

    local function Place(r, h)
        r:ClearAllPoints()
        if up then
            r:SetPoint("BOTTOMLEFT", ns.frame, "BOTTOMLEFT", 0, y)
            r:SetPoint("BOTTOMRIGHT", ns.frame, "BOTTOMRIGHT", 0, y)
        else
            r:SetPoint("TOPLEFT", ns.frame, "TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", ns.frame, "TOPRIGHT", 0, -y)
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
            local h = ns.GetHeader(headerIdx)
            Place(h, ns.HEADER_H)
            h.text:SetText(watch.name .. " (" .. #list .. ")")
            h.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            h:Show()
            y = y + ns.HEADER_H + 4
        end
        for _, entry in ipairs(list) do
            rowIdx = rowIdx + 1
            local r = ns.GetRow(rowIdx)
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
            local h = ns.GetHeader(headerIdx)
            Place(h, ns.HEADER_H)
            h.text:SetText(watch.name .. " (" .. #list .. ")")
            h.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            h:Show()
            y = y + ns.HEADER_H + 4
        end
    end

    -- sections render in watch-list order (per profile)
    for _, watch in ipairs(ns.db.watch) do
        if watch.enabled then
            RenderSection(watch, ns.watched[watch.id] or {}, watch.id == ns.SPELL_POM)
        end
    end
end

ns.frame:SetScript("OnUpdate", Update)