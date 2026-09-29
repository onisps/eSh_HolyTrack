-- ============================================================
-- Renderer: the OnUpdate loop. Scans auras and lays out the bars
-- from the frame's anchor edge (bottom if growing up, top if growing
-- down), one section per enabled watch-list entry.
--
-- Per-entry display modes (watch.mode):
--   "full"    - section header + one bar per target (classic view)
--   "rows"    - bars only, no header (e.g. a single Lifebloom)
--   "summary" - ONE bar: header text drawn over it, bar filled with the
--               remaining time (real time for 1 aura, average for several),
--               left label "Name (N)" where N = number of active auras.
--               Hover shows the per-target breakdown.
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

    -- "summary" mode: single bar with the header over it
    local function RenderSummary(watch, list)
        rowIdx = rowIdx + 1
        local r = ns.GetRow(rowIdx)
        if not r then return end
        Place(r, ns.db.rowHeight)
        r:SetWidth(w)

        local count = #list
        local sum, maxDur, anyExpiry = 0, 0, false
        for _, e in ipairs(list) do
            sum = sum + e.timeLeft
            if e.duration > maxDur then maxDur = e.duration end
            if not e.noExpiry then anyExpiry = true end
        end

        local timeText
        if not anyExpiry then
            -- every aura is permanent (e.g. PoM): full bar, no countdown
            r:SetMinMaxValues(0, 1)
            r:SetValue(1)
            timeText = "--"
        elseif count == 1 then
            local e = list[1]
            r:SetMinMaxValues(0, e.duration)
            r:SetValue(e.timeLeft)
            timeText = ("%.1f"):format(e.timeLeft)
        else
            local avg = sum / count
            r:SetMinMaxValues(0, maxDur)
            r:SetValue(math.min(avg, maxDur))
            timeText = ("%.1f"):format(avg)
        end

        r:SetStatusBarTexture(ns.db.texture)
        local c = watch.color or {1, 1, 1, 1}
        r:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        r.name:SetText(watch.name .. " (" .. count .. ")")
        r.time:SetText(timeText)
        r.unit, r.auraIndex = nil, nil
        r.summaryList = list
        r.summaryTitle = watch.name .. " (" .. count .. ")"
        r:Show()
        y = y + ns.db.rowHeight + 1
    end

    local function RenderSection(watch, list)
        if #list == 0 then return end
        local mode = watch.mode or "full"
        if mode == "summary" then
            return RenderSummary(watch, list)
        end

        local color = watch.color or {1, 1, 1, 1}
        local showHeader = (mode == "full")
        local showStacks = ns.WatchHasPom(watch)

        if not up and showHeader then
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
                r.summaryList = nil
                r:Show()
                y = y + ns.db.rowHeight + 1
            end
        end
        if up and showHeader then
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
            RenderSection(watch, ns.watched[watch] or {})
        end
    end
end

ns.frame:SetScript("OnUpdate", Update)
