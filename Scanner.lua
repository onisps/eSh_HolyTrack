-- ============================================================
-- Scanner: finds tracked auras on group members.
-- Fills ns.watched (map: spellId -> list of entries) every call.
-- Matching is by spell id AND by name (the aura on the target can carry
-- a different id than the cast spell), and only for auras cast by player.
-- ============================================================
local ADDON, ns = ...

ns.watched = {}
local watched = ns.watched

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

function ns.ScanAuras()
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
                if not w and spellId == ns.SPELL_POM_AURA and watchById[ns.SPELL_POM] then
                    w = watchById[ns.SPELL_POM]
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
        if id == ns.SPELL_POM then
            table.sort(list, function(a, b)
                if a.stacks ~= b.stacks then return a.stacks > b.stacks end
                return a.timeLeft < b.timeLeft
            end)
        else
            table.sort(list, function(a, b) return a.timeLeft < b.timeLeft end)
        end
    end
end