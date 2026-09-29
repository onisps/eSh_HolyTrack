-- ============================================================
-- Commands: slash handlers. /eshht and /holytrack open the options
-- tab; /eshht debug prints raw aura data on the current target.
-- ============================================================
local ADDON, ns = ...

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
    ns.OpenOptionsPanel()
end