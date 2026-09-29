-- ============================================================
-- Options: the Interface Options panel ("eSh HolyTrack").
-- Layout: aligned rows in two columns (x=16 / x=230) with horizontal
-- separator lines between sections. Contains:
--   General     - enable tracking, show pets, locked, grow direction
--   Appearance  - bar width/height scale (HandyNotes-style), texture
--                 dropdown (custom, scrollable, with previews), reset
--   Watch list  - scrollable list of tracked spells (add by ID,
--                 checkbox, color swatch, delete)
--   Profiles    - switch / create / delete settings sets
-- ============================================================
local ADDON, ns = ...

local panel
local allPopups = {} -- custom dropdown popups to close when the panel hides

-- per-watch display modes (watch.mode)
local MODES = {
    {label = "Full", value = "full", tip = "Header + one bar per target"},
    {label = "Rows", value = "rows", tip = "Bars only, no header"},
    {label = "Summary", value = "summary", tip = "One bar: count + average time left"},
}

-- forward declarations shared with SavedVars.lua (assigned below)
ns.BuildOptionsPanel = function() end
ns.RefreshAllControls = function() end
ns.OpenOptionsPanel = function() end

-- Re-apply settings after any change (repositions the root frame).
local function RefreshEverything()
    ns.ApplyDB()
end

-- ---------- small UI helpers ----------

local function AddTitle(parent, text, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", size == "big" and "GameFontNormalLarge" or "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

-- horizontal separator line
local function AddSeparator(parent, y)
    local line = parent:CreateTexture(nil, "BACKGROUND")
    line:SetSize(560, 1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    line:SetColorTexture(1, 1, 1, 0.15)
    return line
end

local function AddCheckbox(parent, label, get, set)
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

-- HandyNotes-style scale slider: 0.25..2.00 step 0.01, value shown as
-- "1.25x (250px)". Real size = BASE * scale, derived and stored in db.
local function AddScaleSlider(parent, label, base, get, set)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetWidth(190)
    s:SetHeight(16)
    s:SetMinMaxValues(0.25, 2)
    s:SetValueStep(0.01)
    s:SetObeyStepOnDrag(true)
    s.text = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.text:SetPoint("BOTTOM", s, "TOP", 0, 2)
    s.text:SetText(label)
    s.low = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.low:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 6, -8)
    s.low:SetText("0.25")
    s.high = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.high:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -6, -8)
    s.high:SetText("2.0")
    s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.value:SetPoint("TOPLEFT", s, "TOPRIGHT", 8, -2)
    s:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val * 100 + 0.5) / 100
        self.value:SetText(("%.2fx (%dpx)"):format(val, math.floor(base * val + 0.5)))
        set(val)
    end)
    s.refresh = function()
        s:SetValue(get())
        s.value:SetText(("%.2fx (%dpx)"):format(s:GetValue(), math.floor(base * s:GetValue() + 0.5)))
    end
    return s
end

-- Standard WoW color picker with alpha. Callbacks are cleared BEFORE
-- SetColorRGB/opacity - those fire OnColorSelect, which would otherwise run
-- the PREVIOUS picker's apply() and write this color into the previously
-- edited spell's color table.
local function OpenColorPicker(colorTable, onDone)
    local r, g, b, a = colorTable[1], colorTable[2], colorTable[3], colorTable[4] or 1
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = OpacitySliderFrame:GetValue()
        colorTable[1], colorTable[2], colorTable[3], colorTable[4] = nr, ng, nb, na
        onDone()
    end
    local function cancel(prev)
        colorTable[1], colorTable[2], colorTable[3], colorTable[4] = prev.r, prev.g, prev.b, prev.a
        onDone()
    end
    ColorPickerFrame:SetFrameStrata("TOOLTIP")
    ColorPickerFrame.func = nil
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.cancelFunc = nil
    ColorPickerFrame.hasOpacity = true
    ColorPickerFrame.previousValues = {r = r, g = g, b = b, a = a}
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame.opacity = a
    ColorPickerFrame.func = apply
    ColorPickerFrame.opacityFunc = apply
    ColorPickerFrame.cancelFunc = cancel
    ShowUIPanel(ColorPickerFrame)
end

-- ============================================================
-- Scrollable dropdown widget.
-- UIDropDownMenu in 7.3.5 cannot scroll (DropDownList has no scroll frame),
-- so for long lists (LSM has dozens of textures) we build a custom dropdown:
-- trigger button + popup with a real scroll frame (thumb on the right).
-- Each item shows the texture preview + name.
-- ============================================================
local function MakeScrollDropdown(parent, width, itemsFn, getSel, setSel)
    local dd = CreateFrame("Frame", nil, parent)
    dd:SetSize(width, 24)
    dd:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    dd:SetBackdropColor(0, 0, 0, 0.65)
    dd:EnableMouse(true)

    dd.preview = dd:CreateTexture(nil, "ARTWORK")
    dd.preview:SetSize(34, 12)
    dd.preview:SetPoint("LEFT", dd, "LEFT", 8, 0)

    dd.label = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dd.label:SetPoint("LEFT", dd.preview, "RIGHT", 6, 0)
    dd.label:SetPoint("RIGHT", dd, "RIGHT", -24, 0)
    dd.label:SetJustifyH("LEFT")

    dd.arrow = dd:CreateTexture(nil, "ARTWORK")
    dd.arrow:SetSize(16, 16)
    dd.arrow:SetPoint("RIGHT", dd, "RIGHT", -5, 0)
    dd.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

    dd.btn = CreateFrame("Button", nil, dd)
    dd.btn:SetAllPoints()

    -- popup: bordered list with a scroll frame (scrollbar on the right)
    local popup = CreateFrame("Frame", nil, dd)
    dd.popup = popup
    popup:SetFrameStrata("TOOLTIP")
    popup:SetToplevel(true)
    popup:SetWidth(width + 24)
    popup:SetHeight(200)
    popup:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    popup:SetBackdropColor(0, 0, 0, 0.9)
    popup:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 7, -7)
    scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -27, 7)
    local child = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(child)

    local itemBtns = {}
    local function ItemBtn(i)
        local b = itemBtns[i]
        if not b then
            b = CreateFrame("Button", nil, child)
            b:SetHeight(24)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            b.preview = b:CreateTexture(nil, "ARTWORK")
            b.preview:SetSize(34, 12)
            b.preview:SetPoint("LEFT", b, "LEFT", 6, 0)
            b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.txt:SetPoint("LEFT", b.preview, "RIGHT", 8, 0)
            b.txt:SetPoint("RIGHT", b, "RIGHT", -24, 0)
            b.txt:SetJustifyH("LEFT")
            b.check = b:CreateTexture(nil, "OVERLAY")
            b.check:SetSize(14, 14)
            b.check:SetPoint("RIGHT", b, "RIGHT", -6, 0)
            b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            itemBtns[i] = b
        end
        return b
    end

    local function RefreshPopup()
        local items = itemsFn()
        local sel = getSel()
        for i = 1, math.max(#itemBtns, #items) do
            local b = ItemBtn(i)
            local it = items[i]
            if it then
                b:Show()
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * 24)
                b:SetPoint("RIGHT", child, "RIGHT")
                b.preview:SetTexture(it.path)
                b.txt:SetText(it.name)
                if sel == it.path then
                    b.check:Show()
                else
                    b.check:Hide()
                end
                b:SetScript("OnClick", function()
                    setSel(it.path)
                    dd:UpdateLabel()
                    popup:Hide()
                end)
            else
                b:Hide()
            end
        end
        child:SetWidth(scroll:GetWidth() - 12)
        child:SetHeight(#items * 24 + 4)
    end

    function dd:UpdateLabel()
        local sel = getSel()
        for _, it in ipairs(itemsFn()) do
            if it.path == sel then
                dd.preview:SetTexture(it.path)
                dd.label:SetText(it.name)
                return
            end
        end
        dd.preview:SetTexture(sel)
        dd.label:SetText(sel)
    end

    dd.btn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
        else
            RefreshPopup()
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -3)
            popup:Show()
        end
    end)

    -- close when the mouse leaves both the trigger and the popup
    popup:SetScript("OnUpdate", function(p, dt)
        if MouseIsOver(p) or MouseIsOver(dd) then
            p.away = 0
        else
            p.away = (p.away or 0) + dt
            if p.away > 0.6 then p:Hide() end
        end
    end)

    dd.refresh = function() dd:UpdateLabel() end
    dd:UpdateLabel()
    return dd
end

-- ============================================================
-- Panel construction
-- ============================================================
function ns.BuildOptionsPanel()
    if panel then return end
    panel = CreateFrame("Frame", "eSh_HolyTrackOptions", InterfaceOptionsFramePanelContainer)
    panel.name = "eSh HolyTrack"
    panel:Hide()

    local title = AddTitle(panel, "eSh HolyTrack", "big")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)

    -- ============================================================
    -- Section: General (aligned rows, two columns at x=16 and x=230)
    -- ============================================================
    local cbEnable = AddCheckbox(panel, "Enable tracking",
        function() return ns.db.enabled end,
        function(v) ns.db.enabled = v; RefreshEverything() end)
    cbEnable:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -44)

    local cbPets = AddCheckbox(panel, "Show pets",
        function() return ns.db.showPets end,
        function(v) ns.db.showPets = v end)
    cbPets:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -44)

    local cbLock = AddCheckbox(panel, "Locked (hide drag area)",
        function() return ns.db.locked end,
        function(v) ns.db.locked = v; RefreshEverything() end)
    cbLock:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -72)

    local growLabel = AddTitle(panel, "Grow direction")
    growLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -70)
    local growDD = CreateFrame("Frame", "eSh_HolyTrackGrowDD", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(growDD, 160)
    UIDropDownMenu_JustifyText(growDD, "LEFT")
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
    growDD:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -84)
    growDD.refresh = function() UIDropDownMenu_SetSelectedValue(growDD, ns.db.grow) end

    AddSeparator(panel, -112)

    -- ============================================================
    -- Section: Appearance
    -- ============================================================
    local appTitle = AddTitle(panel, "Appearance", "big")
    appTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -120)

    local sWidth = AddScaleSlider(panel, "Bar width scale", ns.BASE_W,
        function() return ns.db.widthScale end,
        function(v)
            ns.db.widthScale = v
            ns.db.width = math.floor(ns.BASE_W * v + 0.5)
            RefreshEverything()
        end)
    sWidth:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -148)

    local sHeight = AddScaleSlider(panel, "Bar height scale", ns.BASE_H,
        function() return ns.db.heightScale end,
        function(v)
            ns.db.heightScale = v
            ns.db.rowHeight = math.floor(ns.BASE_H * v + 0.5)
            RefreshEverything()
        end)
    sHeight:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -148)

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    local function TextureItems()
        local items = {}
        if LSM then
            for _, name in pairs(LSM:List("statusbar")) do
                items[#items + 1] = {name = name, path = LSM:Fetch("statusbar", name)}
            end
        else
            for _, t in ipairs(ns.FALLBACK_TEXTURES) do
                items[#items + 1] = {name = t[1], path = t[2]}
            end
        end
        table.sort(items, function(a, b) return a.name < b.name end)
        return items
    end

    local texLabel = AddTitle(panel, "Bar texture")
    texLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -196)
    local texDD = MakeScrollDropdown(panel, 190, TextureItems,
        function() return ns.db.texture end,
        function(path)
            ns.db.texture = path
            RefreshEverything()
        end)
    texDD:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -210)
    allPopups[#allPopups + 1] = texDD.popup

    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 22)
    resetBtn:SetText("Reset position")
    resetBtn:SetScript("OnClick", function()
        ns.db.pos = {point = "BOTTOM", relTo = "UIParent", relX = 0, relY = 260}
        RefreshEverything()
        print("|cff00ff00eSh HolyTrack:|r position reset.")
    end)
    resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 230, -211)

    AddSeparator(panel, -244)

    -- ============================================================
    -- Section: Spells to watch
    -- ============================================================
    local watchLabel = AddTitle(panel, "Spells to watch", "big")
    watchLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -252)

    local scroll = CreateFrame("ScrollFrame", "eSh_HolyTrackWatchScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetSize(560, 150)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -274)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(540, 150)
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

            -- "ID | Name" button (click = open the id-group editor)
            r.labelBtn = CreateFrame("Button", nil, r)
            r.labelBtn:SetSize(230, 22)
            r.labelBtn:SetPoint("LEFT", r.icon, "RIGHT", 2, 0)
            r.labelBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            r.label = r.labelBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.label:SetPoint("LEFT", r.labelBtn, "LEFT", 2, 0)

            -- display mode dropdown ("full" | "rows" | "summary");
            -- initialized per-entry in RefreshWatchList (needs the current w)
            r.modeDD = CreateFrame("Frame", "eSh_HolyTrackModeDD" .. i, r, "UIDropDownMenuTemplate")
            r.modeDD:SetPoint("LEFT", r.labelBtn, "RIGHT", -6, -2)
            UIDropDownMenu_SetWidth(r.modeDD, 78)
            UIDropDownMenu_JustifyText(r.modeDD, "LEFT")

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

            -- label: "ids | Name"; auto-name only while the group has one id
            -- and the user has not set a custom one
            if #w.ids == 1 and not w.customName then
                local name = GetSpellInfo(w.ids[1])
                if name then w.name = name end
            end
            local name, _, icon = GetSpellInfo(w.ids[1])
            r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.label:SetText(table.concat(w.ids, "+") .. " | " .. (w.name or "?"))
            r.sw.tex:SetVertexColor(w.color[1], w.color[2], w.color[3], w.color[4] or 1)

            -- mode dropdown: rebuild the menu for the CURRENT watch entry
            UIDropDownMenu_Initialize(r.modeDD, function(self, level)
                for _, m in ipairs(MODES) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = m.label
                    info.value = m.value
                    info.tooltipTitle = m.label
                    info.tooltipText = m.tip
                    info.func = function()
                        w.mode = m.value
                        UIDropDownMenu_SetSelectedValue(r.modeDD, m.value)
                    end
                    info.checked = w.mode == m.value
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            UIDropDownMenu_SetSelectedValue(r.modeDD, w.mode)

            r.cb:SetScript("OnClick", function(self)
                w.enabled = self:GetChecked() and true or false
            end)
            r.cb:SetChecked(w.enabled)

            r.labelBtn:SetScript("OnClick", function()
                OpenIdGroupEditor(w, r)
            end)

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

    -- ============================================================
    -- ID group editor: click the "ids | Name" label to open a popup
    -- listing the tracked ids of one watch entry; remove with X, add
    -- by typing an id. Lets several spell ids share one section
    -- (e.g. both Rejuvenation ids with Germination).
    -- ============================================================
    local editor = CreateFrame("Frame", "eSh_HolyTrackIdGroupEditor", panel)
    editor:SetSize(250, 120)
    editor:SetFrameStrata("TOOLTIP")
    editor:SetToplevel(true)
    editor:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    editor:SetBackdropColor(0, 0, 0, 0.92)
    editor:Hide()
    allPopups[#allPopups + 1] = editor

    editor.title = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editor.title:SetPoint("TOPLEFT", editor, "TOPLEFT", 10, -8)
    editor.title:SetPoint("RIGHT", editor, "RIGHT", -10, 0)
    editor.title:SetJustifyH("LEFT")

    editor.input = CreateFrame("EditBox", "eSh_HolyTrackIdGroupAddBox", editor, "InputBoxTemplate")
    editor.input:SetSize(80, 20)
    editor.input:SetAutoFocus(false)
    editor.input:SetNumeric(true)
    editor.input:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 12, 8)
    editor.addBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    editor.addBtn:SetSize(50, 20)
    editor.addBtn:SetText("Add")
    editor.addBtn:SetPoint("LEFT", editor.input, "RIGHT", 6, 0)
    editor.closeBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    editor.closeBtn:SetSize(20, 20)
    editor.closeBtn:SetText("x")
    editor.closeBtn:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -6, -6)

    local chipBtns = {}
    for j = 1, 8 do
        local chip = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
        chip:SetSize(230, 18)
        chip:SetPoint("TOPLEFT", editor, "TOPLEFT", 10, -26 - (j - 1) * 20)
        chip:SetNormalFontObject("GameFontHighlightSmall")
        chip.chipDel = chip:CreateTexture(nil, "OVERLAY")
        chip.chipDel:SetSize(10, 10)
        chip.chipDel:SetPoint("RIGHT", chip, "RIGHT", -4, 0)
        chip.chipDel:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        chipBtns[j] = chip
    end

    local function RemoveId(w, id)
        if #w.ids <= 1 then
            print("|cff00ff00eSh HolyTrack:|r a watch entry needs at least one id (delete the row instead).")
            return
        end
        for j, other in ipairs(w.ids) do
            if other == id then
                table.remove(w.ids, j)
                break
            end
        end
        w.id = w.ids[1]
        ns.RefreshWatchList()
        OpenIdGroupEditor(w) -- refresh popup content
    end

    editor.addBtn:SetScript("OnClick", function()
        local w = editor.w
        if not w then return end
        local id = tonumber(editor.input:GetText())
        if not id then
            print("|cff00ff00eSh HolyTrack:|r enter a numeric spell ID.")
            return
        end
        if not GetSpellInfo(id) then
            print("|cff00ff00eSh HolyTrack:|r no spell with ID " .. id .. ".")
            return
        end
        for _, other in ipairs(w.ids) do
            if other == id then
                print("|cff00ff00eSh HolyTrack:|r id " .. id .. " is already in this group.")
                return
            end
        end
        w.ids[#w.ids + 1] = id
        w.id = w.ids[1]
        editor.input:SetText("")
        if #w.ids == 2 then
            -- first group: freeze the name so GetSpellInfo doesn't overwrite it
            w.customName = true
        end
        ns.RefreshWatchList()
        OpenIdGroupEditor(w)
    end)
    editor.closeBtn:SetScript("OnClick", function() editor:Hide() end)

    function OpenIdGroupEditor(w, row)
        if editor:IsShown() and editor.w == w then
            editor:Hide()
            return
        end
        editor.w = w
        editor.title:SetText(table.concat(w.ids, "+") .. " | " .. (w.name or "?"))
        for j, chip in ipairs(chipBtns) do
            local id = w.ids[j]
            if id then
                local spellName = GetSpellInfo(id)
                chip:SetText((spellName or "?") .. "  [" .. id .. "]")
                chip:SetScript("OnClick", function()
                    RemoveId(w, id)
                end)
                chip:Show()
            else
                chip:Hide()
            end
        end
        editor:ClearAllPoints()
        if row then
            editor:SetPoint("LEFT", row, "RIGHT", 8, 0)
        else
            editor:SetPoint("CENTER", UIParent, "CENTER")
        end
        editor:Show()
    end

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
            local wIds = w.ids or {w.id}
            for _, wid in ipairs(wIds) do
                if wid == id then
                    print("|cff00ff00eSh HolyTrack:|r '" .. name .. "' is already in the watch list.")
                    return
                end
            end
        end
        ns.db.watch[#ns.db.watch + 1] = {id = id, ids = {id}, name = name, enabled = true, mode = "full", color = {1, 0.7, 0.2, 1}}
        idInput:SetText("")
        RefreshWatchList()
        print("|cff00ff00eSh HolyTrack:|r now watching '" .. name .. "' (id " .. id .. ").")
    end)

    AddSeparator(panel, -466)

    -- ============================================================
    -- Section: Profiles
    -- ============================================================
    local profLabel = AddTitle(panel, "Profiles (settings sets)", "big")
    profLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -474)

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
    profDD:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -494)
    profDD.refresh = function() UIDropDownMenu_SetSelectedValue(profDD, eSh_HolyTrackDB.activeProfile) end

    -- create / delete profile
    local newInput = CreateFrame("EditBox", "eSh_HolyTrackNewProfileBox", panel, "InputBoxTemplate")
    newInput:SetSize(140, 20)
    newInput:SetAutoFocus(false)
    newInput:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -540)
    local createBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    createBtn:SetSize(80, 22)
    createBtn:SetText("Create")
    createBtn:SetPoint("LEFT", newInput, "RIGHT", 10, 0)
    createBtn:SetScript("OnClick", function()
        local name = newInput:GetText()
        if name ~= "" and not eSh_HolyTrackDB.profiles[name] then
            eSh_HolyTrackDB.profiles[name] = {}
            ns.SwitchProfile(name)
            ns.RefreshAllControls()
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
        ns.RefreshAllControls()
        print("|cff00ff00eSh HolyTrack:|r profile '" .. name .. "' deleted. Switched to '" .. fallback .. "'.")
    end)

    -- close custom popups when the options panel hides
    panel:HookScript("OnHide", function()
        for _, p in ipairs(allPopups) do p:Hide() end
    end)
    panel:SetScript("OnShow", function()
        RefreshWatchList()
    end)

    InterfaceOptions_AddCategory(panel)
end

-- Re-sync all controls from the active profile.
function ns.RefreshAllControls()
    if not panel then return end
    for _, child in pairs({panel:GetChildren()}) do
        if child.refresh then child.refresh() end
    end
    if ns.RefreshWatchList then ns.RefreshWatchList() end
end

-- Open the tab (7.3.5 needs the double OpenToCategory call).
function ns.OpenOptionsPanel()
    if not panel then
        print("|cff00ff00eSh HolyTrack:|r not initialized yet.")
        return
    end
    ns.RefreshAllControls()
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
end