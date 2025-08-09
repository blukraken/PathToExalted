-- Frames, dropdowns, painting, skinning
local ADDON_NAME, ns = ...
ns.UI = ns.UI or {}

local UI = ns.UI

local ROW_HEIGHT = 22
local MAX_ROWS   = 16
local COLW_NAME, COLW_TYPE, COLW_LEVEL, COLW_PROG, COLW_EXTRA = 230, 70, 110, 80, 100

local function _DD_SetText(drop, text)
    local fs = _G[drop:GetName().."Text"]
    if fs then fs:SetText(text) end
end

local function _DD_Normalize(dd, width)
    if not dd or not dd.GetName then return end
    UIDropDownMenu_SetWidth(dd, width or 140)
    dd:SetHeight(22)

    local name  = dd:GetName()
    local btn   = _G[name.."Button"]
    local text  = _G[name.."Text"]
    local icon  = _G[name.."Icon"]

    if btn then
        btn:ClearAllPoints()
        btn:SetAllPoints(dd)
        btn:SetHitRectInsets(0, 0, 0, 0)
    end
    if text then
        text:ClearAllPoints()
        text:SetPoint("LEFT", dd, "LEFT", 12, 0)
        text:SetPoint("RIGHT", dd, "RIGHT", -24, 0)
        text:SetJustifyH("LEFT")
    end
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("RIGHT", dd, "RIGHT", -8, 0)
    end
end

local function _DD_Lock(dd, width, height)
    if not dd or not dd.GetName then return end
    width  = width  or 140
    height = height or 22

    UIDropDownMenu_SetWidth(dd, width)
    dd:SetHeight(height)

    local name = dd:GetName()
    local btn  = _G[name.."Button"]
    local text = _G[name.."Text"]
    local icon = _G[name.."Icon"]

    if btn then
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", dd, "TOPLEFT", 0, 0)
        btn:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 0, 0)
        btn:SetHitRectInsets(0,0,0,0)
        btn:SetHeight(height)
    end
    if text then
        text:ClearAllPoints()
        text:SetPoint("LEFT", dd, "LEFT", 12, 0)
        text:SetPoint("RIGHT", dd, "RIGHT", -24, 0)
        text:SetJustifyH("LEFT")
    end
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("RIGHT", dd, "RIGHT", -8, 0)
    end
    if dd.backdrop and dd.backdrop.SetAllPoints then
        dd.backdrop:SetAllPoints(dd)
    end

    -- If any skin tries to resize later, snap back
    dd:HookScript("OnSizeChanged", function(self)
        self:SetHeight(height)
        if self.backdrop and self.backdrop.SetAllPoints then
            self.backdrop:SetAllPoints(self)
        end
        if btn then btn:SetHeight(height) end
    end)
end

-- ElvUI / AddOn helpers (11.x safe)
local function AddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    elseif IsAddOnLoaded then
        return IsAddOnLoaded(name)
    end
    return false
end

local function SafeCreateBackdrop(frame, E, transparent)
    if not frame then return end
    frame:SetBackdrop(nil)
    if frame.CreateBackdrop then
        frame:CreateBackdrop(transparent and "Transparent" or nil, true, true)
    elseif E and E.CreateBackdrop then
        E:CreateBackdrop(frame, transparent and "Transparent" or nil, true, true)
    else
        -- Last resort: simple Blizzard backdrop so we still look boxed
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        frame:SetBackdropColor(0,0,0, transparent and 0.7 or 0.5)
        frame:SetBackdropBorderColor(0,0,0,0.8)
    end
end

local function SafeFontTemplate(fs, E)
    if not fs then return end
    if fs.FontTemplate then
        fs:FontTemplate()
        return
    end
    if E and E.Libs and E.Libs.LSM and E.db and E.db.general and E.db.general.font then
        local font = E.Libs.LSM:Fetch("font", E.db.general.font)
        if font then fs:SetFont(font, 12, "") end
    end
    -- Ensure readable white even if we couldn't fetch Elv font
    local r,g,b = fs:GetTextColor()
    if r == 1 and g == 0.82 and b == 0 then -- default yellow-ish
        fs:SetTextColor(1,1,1)
    end
end

-- Ensure dropdown popups appear above our panels
hooksecurefunc("ToggleDropDownMenu", function(level)
    local list = _G["DropDownList"..(level or 1)]
    if list and list:IsShown() then list:SetFrameStrata("DIALOG") end
end)

-- simple "fake dropdown" using MenuUtil (Retail-safe)
local function CreateChoiceButton(parent, width)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 160, 22)
    btn._label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn._label:SetPoint("CENTER")
    btn.SetLabel = function(self, txt) self._label:SetText(txt) end
    btn.GetLabel = function(self) return self._label:GetText() end
    return btn
end


-- public: build window
function UI.CreateMainWindow(self)  -- self is the AceAddon
    if self.MainWindow then return end
    local cfg = self.db.profile.window

    local f = CreateFrame("Frame", "P2E_MainWindow", UIParent, "BackdropTemplate")
    f:SetSize(cfg.w, cfg.h)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cfg.x, cfg.y)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local _, _, _, x, y = frame:GetPoint(1)
        cfg.x, cfg.y = x, y
    end)
    f:SetAlpha(cfg.alpha or 1)
    f:SetClampedToScreen(true)

    -- auto scan when shown
    f:SetScript("OnShow", function()
        self:ScanReputations()
        self:RefreshView()
    end)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Path to Exalted")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide(); self.db.profile.window.shown = false end)

    -- two-row filters
    local filters = CreateFrame("Frame", nil, f)
    filters:SetPoint("TOPLEFT", 12, -40)
    filters:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -40)
    filters:SetHeight(60)

    local function NewLabel(parent, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetText(text)
        return fs
    end

    local row1 = CreateFrame("Frame", nil, filters); row1:SetHeight(26)
    row1:SetPoint("TOPLEFT", filters, "TOPLEFT", 0, 0)
    row1:SetPoint("TOPRIGHT", filters, "TOPRIGHT", 0, 0)

    local typeLabel = NewLabel(row1, "Type:"); typeLabel:SetPoint("LEFT", row1, "LEFT", 0, 0)
    local typeDrop = CreateFrame("Frame", "P2E_TypeDropdown", row1, "UIDropDownMenuTemplate")
    typeDrop:SetPoint("LEFT", typeLabel, "RIGHT", 2, -2); UIDropDownMenu_SetWidth(typeDrop, 120)
    _DD_Normalize(typeDrop, 120) _DD_Lock(typeDrop, 120, 22)

    local statusLabel = NewLabel(row1, "Status:"); statusLabel:SetPoint("LEFT", typeDrop, "RIGHT", 20, 0)
    local statusDrop = CreateFrame("Frame", "P2E_StatusDropdown", row1, "UIDropDownMenuTemplate")
    statusDrop:SetPoint("LEFT", statusLabel, "RIGHT", 2, -2); UIDropDownMenu_SetWidth(statusDrop, 140)
    _DD_Normalize(statusDrop, 140) _DD_Lock(statusDrop, 140, 22)

    local row2 = CreateFrame("Frame", nil, filters); row2:SetHeight(26)
    row2:SetPoint("TOPLEFT", row1, "BOTTOMLEFT", 0, -4)
    row2:SetPoint("TOPRIGHT", row1, "BOTTOMRIGHT", 0, -4)

    local sortLabel = NewLabel(row2, "Sort:"); sortLabel:SetPoint("LEFT", row2, "LEFT", 0, 0)
    local sortDrop = CreateFrame("Frame", "P2E_SortDropdown", row2, "UIDropDownMenuTemplate")
    sortDrop:SetPoint("LEFT", sortLabel, "RIGHT", 2, -2); UIDropDownMenu_SetWidth(sortDrop, 140)
    _DD_Normalize(sortDrop, 140) _DD_Lock(sortDrop, 140, 22)

    f.filters = { typeDrop = typeDrop, statusDrop = statusDrop, sortDrop = sortDrop }

    -- Ensure filters sit above the header so clicks aren't eaten
    filters:SetFrameLevel(f:GetFrameLevel() + 5)
    row1:SetFrameLevel(filters:GetFrameLevel() + 1)
    row2:SetFrameLevel(filters:GetFrameLevel() + 1)
    typeDrop:SetFrameLevel(filters:GetFrameLevel() + 2)
    statusDrop:SetFrameLevel(filters:GetFrameLevel() + 2)
    sortDrop:SetFrameLevel(filters:GetFrameLevel() + 2)

    -- header
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -10)
    header:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    header:SetHeight(22)
    header:EnableMouse(false)
    header:SetFrameStrata("BACKGROUND")
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    header:SetBackdropColor(0,0,0,0.2)
    header:SetBackdropBorderColor(0,0,0,0.4)

    f.header = header

    local function NewHeaderText(parent, text, w, point, xOff)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetText(text); fs:SetJustifyH("LEFT"); fs:SetPoint("LEFT", parent, point or "LEFT", xOff or 0, 0); fs:SetWidth(w)
        return fs
    end

    NewHeaderText(header, "Name",     COLW_NAME,  "LEFT", 6)
    NewHeaderText(header, "Type",     COLW_TYPE,  "LEFT", 12 + COLW_NAME)
    NewHeaderText(header, "Level",    COLW_LEVEL, "LEFT", 18 + COLW_NAME + COLW_TYPE)
    NewHeaderText(header, "Progress", COLW_PROG,  "LEFT", 24 + COLW_NAME + COLW_TYPE + COLW_LEVEL)
    NewHeaderText(header, "Details",  COLW_EXTRA, "LEFT", 30 + COLW_NAME + COLW_TYPE + COLW_LEVEL + COLW_PROG)

    -- scroll & rows
    local scroll = CreateFrame("ScrollFrame", "P2E_ScrollFrame", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 12)
    f.rows = {}

    local function CreateRow(index)
        local row = CreateFrame("Button", nil, f, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", f, "LEFT", 12, 0)
        row:SetPoint("RIGHT", f, "RIGHT", -12, 0)
        if index == 1 then row:SetPoint("TOP", scroll, "TOP", 0, 0)
        else row:SetPoint("TOP", f.rows[index-1], "BOTTOM", 0, -2) end

        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        row:SetBackdropColor(0,0,0,0.05)
        row:SetBackdropBorderColor(0,0,0,0.12)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        row.name  = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.type  = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.prog  = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.extra = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

        row.name:SetPoint("LEFT", row, "LEFT", 6, 0);                                    row.name:SetWidth(COLW_NAME)
        row.type:SetPoint("LEFT", row, "LEFT", 12 + COLW_NAME, 0);                       row.type:SetWidth(COLW_TYPE)
        row.level:SetPoint("LEFT", row, "LEFT", 18 + COLW_NAME + COLW_TYPE, 0);          row.level:SetWidth(COLW_LEVEL)
        row.prog:SetPoint("LEFT", row, "LEFT", 24 + COLW_NAME + COLW_TYPE + COLW_LEVEL, 0); row.prog:SetWidth(COLW_PROG)
        row.extra:SetPoint("LEFT", row, "LEFT", 30 + COLW_NAME + COLW_TYPE + COLW_LEVEL + COLW_PROG, 0); row.extra:SetWidth(COLW_EXTRA)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row:SetScript("OnEnter", function(selfR)
            if not selfR._data then return end
            GameTooltip:SetOwner(selfR, "ANCHOR_RIGHT")
            local r = selfR._data
            GameTooltip:AddLine(r.name or "")
            if r.type == "renown" then
                GameTooltip:AddLine(("Renown: %d / %d"):format(r.renownLevel or 0, r.renownCap or 0), 1,1,1)
            else
                GameTooltip:AddLine(("StandingID: %s  (%d / %d)"):format(tostring(r.standingID or "?"), r.current or 0, r.max or 0), 1,1,1)
            end
            if r.isWarband then GameTooltip:AddLine("Warband-wide", 0.6, 0.9, 1) else GameTooltip:AddLine("Character-specific", 1, 0.85, 0.4) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Click handlers
        row:SetScript("OnClick", function(selfR, btn)
            if not selfR._data then return end
            local addon = ns and ns.UI and ns.UI._addonRef
            if not addon then return end
            if btn == "RightButton" then
                UI.ShowRowContextMenu(addon, selfR._data)
            else
                if addon.ShowGoalPanel then
                    addon:ShowGoalPanel(selfR._data)
                end
            end
        end)
        return row
    end

    for i = 1, MAX_ROWS do f.rows[i] = CreateRow(i) end

    f.scroll = scroll
    self.MainWindow = f
    ns.UI._addonRef = self

    if not UI.ContextMenu then
        UI.ContextMenu = CreateFrame("Frame", "P2E_RowContextMenu", UIParent)
    end

    UI.InitDropdowns(self)

    scroll:SetScript("OnVerticalScroll", function(selfScroll, offset)
        FauxScrollFrame_OnVerticalScroll(selfScroll, offset, ROW_HEIGHT + 2, function() self:RefreshRows() end)
    end)

    self:TrySkinElvUI(f, close)
    self:RefreshRows()
end

function UI.InitDropdowns(self)
    local f = self.MainWindow; if not f then return end
    local filters = self.db.profile.filters

    -- helper: works on Retail 11.x and Classic
    local function ConfigureDD(dd, initFn)
        if dd._p2eConfigured then return end
        -- prefer the newer setter if present
        if _G.UIDropDownMenu_SetInitializeFunction then
            UIDropDownMenu_SetInitializeFunction(dd, initFn)
        else
            UIDropDownMenu_Initialize(dd, initFn)
        end
        -- show the list under the dropdown
        UIDropDownMenu_SetAnchor(dd, 0, 0, "TOPLEFT", dd, "BOTTOMLEFT")
        dd._p2eConfigured = true
    end

    -- TYPE
    ConfigureDD(f.filters.typeDrop, function(selfDD, level)
        if level ~= 1 then return end
        for _, v in ipairs({ "All", "faction", "renown" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.func = function()
                filters.type = v
                _DD_SetText(f.filters.typeDrop, v)
                self:RefreshView()
            end
            info.checked = (filters.type == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetWidth(f.filters.typeDrop, 120)
    _DD_SetText(f.filters.typeDrop, filters.type or "All")

    -- STATUS
    ConfigureDD(f.filters.statusDrop, function(selfDD, level)
        if level ~= 1 then return end
        for _, v in ipairs({ "All", "In-Progress", "Maxed" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.func = function()
                filters.status = v
                _DD_SetText(f.filters.statusDrop, v)
                self:RefreshView()
            end
            info.checked = (filters.status == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetWidth(f.filters.statusDrop, 140)
    _DD_SetText(f.filters.statusDrop, filters.status or "All")

    -- SORT
    ConfigureDD(f.filters.sortDrop, function(selfDD, level)
        if level ~= 1 then return end
        for _, v in ipairs({ "Progress", "Name" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.func = function()
                filters.sort = v
                _DD_SetText(f.filters.sortDrop, v)
                self:RefreshView()
            end
            info.checked = (filters.sort == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetWidth(f.filters.sortDrop, 140)
    _DD_SetText(f.filters.sortDrop, filters.sort or "Progress")
end


function UI.RefreshRows(self)
    if not self.MainWindow then return end
    local rows = ns.Data.GetRows()
    local scroll = self.MainWindow.scroll
    local total  = #rows
    local offset = FauxScrollFrame_GetOffset(scroll) or 0
    FauxScrollFrame_Update(scroll, total, 16, ROW_HEIGHT + 2)

    for i = 1, 16 do
        local idx = i + offset
        local row = self.MainWindow.rows[i]
        local r = rows[idx]
        if r then
            row._data = r; row:Show()
            row.name:SetText(r.name or "?")
            row.type:SetText(r.type == "renown" and "Renown" or "Faction")
            if r.type == "renown" then
                local cur, cap = r.renownLevel or 0, r.renownCap or 0
                row.level:SetText(("%d / %d"):format(cur, cap))
                row.prog:SetText(("%d%%"):format(ns.Data.Pct(cur, cap)))
                row.extra:SetText(r.isWarband and "Warband" or "")
                row:SetBackdropColor((cur >= cap and cap > 0) and 0.08 or 0, 0.18, (cur >= cap and cap > 0) and 0.08 or 0, (cur >= cap and cap > 0) and 0.20 or 0.05)
            else
                local cur, maxv = r.current or 0, r.max or 0
                row.level:SetText(("%d / %d"):format(cur, maxv))
                row.prog:SetText(("%d%%"):format(ns.Data.Pct(cur, maxv)))
                row.extra:SetText(("Standing %s"):format(tostring(r.standingID or "?")))
                local maxed = (maxv > 0 and cur >= maxv)
                row:SetBackdropColor(maxed and 0.08 or 0, 0.18, maxed and 0.08 or 0, maxed and 0.20 or 0.05)
            end
        else
            row._data = nil
            row:Hide()
        end
    end
end

function UI.TrySkinElvUI(self, frame, close)
    if not AddOnLoaded("ElvUI") or not ElvUI then return end
    local E = unpack(ElvUI)
    local S = E and E:GetModule("Skins", true)
    if not E or not S then return end

    local function SkinFrameOnce(box, transparent)
        if not box or box._p2eElvSkinned then return end
        SafeCreateBackdrop(box, E, transparent)
        box._p2eElvSkinned = true
    end

    local function SkinFontsOnce(box)
        if not box or box._p2eFontSkinned then return end
        local regions = { box:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                SafeFontTemplate(r, E)
            end
        end
        box._p2eFontSkinned = true
    end

    -- Main frame
    local f = self.MainWindow or frame
    if f then
        SkinFrameOnce(f, true)
        SkinFontsOnce(f)
        if close and S.HandleCloseButton then S:HandleCloseButton(close) end

        -- Filters (dropdowns)
        if f.filters and S.HandleDropDownBox then
            S:HandleDropDownBox(f.filters.typeDrop,   140)
            _DD_Normalize(f.filters.typeDrop, 140)
            _DD_Lock(f.filters.typeDrop, 120, 22)
            S:HandleDropDownBox(f.filters.statusDrop, 140)
            _DD_Normalize(f.filters.statusDrop, 140)
            _DD_Lock(f.filters.statusDrop, 140, 22)
            S:HandleDropDownBox(f.filters.sortDrop,   140)
            _DD_Normalize(f.filters.sortDrop, 140)
            _DD_Lock(f.filters.sortDrop, 140, 22)

            -- Ensure dropdown text does not overlap the arrow button
            local function FixDropdownTextPadding(dd)
                if not dd or not dd.GetName then return end
                local textRegion = _G[dd:GetName().."Text"]
                if not textRegion then return end
                textRegion:ClearAllPoints()
                -- Left padding for the icon/left cap, right padding to leave room for arrow
                textRegion:SetPoint("LEFT", dd, "LEFT", 20, 0)
                textRegion:SetPoint("RIGHT", dd, "RIGHT", -22, 0)
                textRegion:SetJustifyH("LEFT")
            end
            FixDropdownTextPadding(f.filters.typeDrop)
            FixDropdownTextPadding(f.filters.statusDrop)
            FixDropdownTextPadding(f.filters.sortDrop)
        end

        -- Header fonts only (we don't want a box here)
        if f.header then
            SkinFontsOnce(f.header)
            f.header:SetBackdrop(nil)
            if f.header.backdrop then f.header.backdrop:Hide() end
        end

        -- Main list scrollbar
        if f.scroll and f.scroll.ScrollBar and S.HandleScrollBar then
            S:HandleScrollBar(f.scroll.ScrollBar)
        end

        -- Rows
        if f.rows then
            for i = 1, #f.rows do
                local r = f.rows[i]
                if r and not r._p2eElvRow then
                    r:SetBackdrop(nil)
                    SafeCreateBackdrop(r, E, false)
                    if r.backdrop and r.backdrop.SetAllPoints then r.backdrop:SetAllPoints() end
                    SafeFontTemplate(r.name,  E); if r.name  then r.name:SetTextColor(1,0.82,0) end
                    SafeFontTemplate(r.type,  E)
                    SafeFontTemplate(r.level, E)
                    SafeFontTemplate(r.prog,  E)
                    SafeFontTemplate(r.extra, E); if r.extra then r.extra:SetTextColor(.85,.85,.85) end
                    r._p2eElvRow = true
                end
            end
        end
    end

    -- Goal panel
    local gp = (self.MainWindow and self.MainWindow._goalPanel) or (frame and frame._goalPanel)
    if gp then
        SkinFrameOnce(gp, true)
        SkinFontsOnce(gp)
        if gp.save and S.HandleButton then S:HandleButton(gp.save) end
        if gp.clear and S.HandleButton then S:HandleButton(gp.clear) end
        if gp.renownSlider and S.HandleSliderFrame then S:HandleSliderFrame(gp.renownSlider) end
        if gp.standingDrop and S.HandleDropDownBox then S:HandleDropDownBox(gp.standingDrop, 160) end
        if gp.scroll and gp.scroll.ScrollBar and S.HandleScrollBar then
            S:HandleScrollBar(gp.scroll.ScrollBar)
        end
        if gp.rows then
            for i = 1, #gp.rows do
                local r = gp.rows[i]
                if r and not r._p2eElvRow then
                    r:SetBackdrop(nil)
                    SafeCreateBackdrop(r, E, false)
                    if r.backdrop and r.backdrop.SetAllPoints then r.backdrop:SetAllPoints() end
                    SafeFontTemplate(r.name,  E)
                    SafeFontTemplate(r.rep,   E)
                    SafeFontTemplate(r.reset, E); if r.reset then r.reset:SetTextColor(.85,.85,.85) end
                    r._p2eElvRow = true
                end
            end
        end
    end
end


-- ===== Goal Panel =====
function UI.ShowGoalPanel(self, row)
    if not self.MainWindow then return end
    if not row or not row.factionID then return end

    local parent = self.MainWindow
    if not parent._goalPanel then
        local gp = CreateFrame("Frame", "P2E_GoalPanel", UIParent, "BackdropTemplate")

        -- Dock outside to the right of main window
        gp:SetPoint("TOPLEFT", parent, "TOPRIGHT", 1, -40)
        gp:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 1, 10)
        gp:SetWidth(360)
        gp:SetClampedToScreen(true)
        gp:SetFrameStrata("DIALOG")
        parent:HookScript("OnHide", function() gp:Hide() end)

        gp:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 }
        })

        gp.title = gp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        gp.title:SetPoint("TOPLEFT", 12, -10)
        gp.title:SetText("Goal Settings")

        local close = CreateFrame("Button", nil, gp, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        close:SetScript("OnClick", function() gp:Hide() end)

        gp.curText = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gp.curText:SetPoint("TOPLEFT", gp.title, "BOTTOMLEFT", 0, -6)
        gp.curText:SetText("Current: -")

        gp.targetLabel = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gp.targetLabel:SetPoint("TOPLEFT", gp.curText, "BOTTOMLEFT", 0, -8)
        gp.targetLabel:SetText("Target:")

        gp.renownSlider = CreateFrame("Slider", "P2E_GoalRenownSlider", gp, "OptionsSliderTemplate")
        gp.renownSlider:SetWidth(220)
        gp.renownSlider:SetHeight(16)
        gp.renownSlider:SetPoint("TOPLEFT", gp.targetLabel, "BOTTOMLEFT", 0, -8)  -- directly under the Target label
        gp.renownSlider:SetMinMaxValues(1, row.renownCap or 30)
        gp.renownSlider:SetValueStep(1)
        gp.renownSlider:Hide()
        gp.renownValue = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gp.renownValue:SetPoint("LEFT", gp.renownSlider, "RIGHT", 10, 0)
        gp.renownValue:SetText("")

        -- Low label
        gp.lowText = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gp.lowText:SetText("Low")
        gp.lowText:SetPoint("TOPLEFT", gp.renownSlider, "BOTTOMLEFT", 0, -2)

        -- High label
        gp.highText = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gp.highText:SetText("High")
        gp.highText:SetPoint("TOPRIGHT", gp.renownSlider, "BOTTOMRIGHT", 0, -2)

        gp.standingDrop = CreateFrame("Frame", "P2E_TargetStanding", gp, "UIDropDownMenuTemplate")
        gp.standingDrop:SetPoint("TOPLEFT", gp.targetLabel, "BOTTOMLEFT", -14, -6)
        gp.standingDrop:Hide()

        gp.save = CreateFrame("Button", nil, gp, "UIPanelButtonTemplate")
        gp.save:SetSize(80, 22)
        gp.save:SetPoint("TOPLEFT", gp.targetLabel, "BOTTOMLEFT", 0, -50)
        gp.save:SetText("Save")

        gp.clear = CreateFrame("Button", nil, gp, "UIPanelButtonTemplate")
        gp.clear:SetSize(80, 22)
        gp.clear:SetPoint("LEFT", gp.save, "RIGHT", 8, 0)
        gp.clear:SetText("Clear")

        gp.taskHeader = gp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gp.taskHeader:SetPoint("TOPLEFT", gp.save, "BOTTOMLEFT", 0, -10)
        gp.taskHeader:SetText("Suggested Tasks")

        gp.scroll = CreateFrame("ScrollFrame", nil, gp, "FauxScrollFrameTemplate")
        gp.scroll:SetPoint("TOPLEFT", gp.taskHeader, "BOTTOMLEFT", 0, -4)
        gp.scroll:SetPoint("BOTTOMRIGHT", gp, "BOTTOMRIGHT", -26, 10)

        gp.rows = {}
        local function NewTaskRow(idx)
            local r = CreateFrame("Button", nil, gp, "BackdropTemplate")
            r:SetHeight(18)
            if idx == 1 then
                r:SetPoint("TOPLEFT", gp.scroll, "TOPLEFT", 4, 0)
                r:SetPoint("TOPRIGHT", gp.scroll, "TOPRIGHT", -20, 0)
            else
                r:SetPoint("TOPLEFT", gp.rows[idx-1], "BOTTOMLEFT", 0, -2)
                r:SetPoint("TOPRIGHT", gp.rows[idx-1], "BOTTOMRIGHT", 0, -2)
            end
            r:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
                tile = false, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            r:SetBackdropColor(0,0,0,0.04)
            r:SetBackdropBorderColor(0,0,0,0.10)

            r.name  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.rep   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.reset = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

            r.name:ClearAllPoints()
            r.name:SetPoint("LEFT", r, "LEFT", 6, 0)
            r.name:SetPoint("RIGHT", r, "RIGHT", -130, 0)     -- flexible name column
            r.name:SetJustifyH("LEFT")
            r.name:SetWordWrap(false)

            r.rep:ClearAllPoints()
            r.rep:SetPoint("RIGHT", r, "RIGHT", -70, 0)       -- numeric column
            r.rep:SetWidth(60)
            r.rep:SetJustifyH("RIGHT")
            r.rep:SetWordWrap(false)

            r.reset:ClearAllPoints()
            r.reset:SetPoint("RIGHT", r, "RIGHT", -6, 0)      -- reset label
            r.reset:SetWidth(60)
            r.reset:SetJustifyH("RIGHT")
            r.reset:SetWordWrap(false)

            r:SetScript("OnClick", function(selfR)
                if not selfR._data or not selfR._data.activityKey then return end
                if ns.Goals and ns.Goals.MarkCompleted then
                    ns.Goals.MarkCompleted(self.db, self._factionID, selfR._data.activityKey)
                    UI.RefreshGoalTasks(self)
                end
            end)
            return r
        end
        for i=1, 8 do gp.rows[i] = NewTaskRow(i) end

        self:TrySkinElvUI(gp, close)
        if AddOnLoaded("ElvUI") and ElvUI and gp.standingBtn then
            local E = unpack(ElvUI); local S = E and E:GetModule("Skins", true)
            if S and S.HandleButton then S:HandleButton(gp.standingBtn) end
        end
        parent._goalPanel = gp
    end

    local gp = parent._goalPanel
    gp:Show()

    gp._row = row
    gp._factionID = row.factionID
    gp.title:SetText(("Goal: %s"):format(row.name or ""))

    if row.type == "renown" then
        -- show the slider for renown
        gp.standingDrop:Hide()
        gp.renownSlider:Show()

        local s = gp.renownSlider
        local cur = row.renownLevel or 0
        local cap = (row.renownCap and row.renownCap > 0) and row.renownCap or math.max(cur, 30)

        -- place the slider directly under the "Target:" label
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", gp.targetLabel, "BOTTOMLEFT", 0, -8)
        s:SetPoint("RIGHT", gp, "RIGHT", -80, 0)   -- leave space for the numeric value on the right
        s:SetMinMaxValues(1, cap)
        s:SetValueStep(1)
        s:SetValue(math.max(cur, 1))

        -- value number to the right of the slider
        gp.renownValue:ClearAllPoints()
        gp.renownValue:SetPoint("LEFT", s, "RIGHT", 8, 0)
        gp.renownSlider:SetScript("OnValueChanged", function(_, v)
            gp.renownValue:SetText(("%d"):format(v))
        end)
        gp.renownValue:SetText(("%d"):format(s:GetValue()))

        -- force the Low/High labels to sit just under the slider
        local low  = s.Low  or gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local high = s.High or gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.Low, s.High = low, high
        low:SetText("Low")
        high:SetText("High")
        low:ClearAllPoints();  low:SetPoint ("TOPLEFT",  s, "BOTTOMLEFT",  0, -2)
        high:ClearAllPoints(); high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)

        -- buttons go *below* the slider + labels
        gp.save:ClearAllPoints()
        gp.save:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -22)
        gp.clear:ClearAllPoints()
        gp.clear:SetPoint("LEFT", gp.save, "RIGHT", 8, 0)

        -- and the task header follows the buttons
        gp.taskHeader:ClearAllPoints()
        gp.taskHeader:SetPoint("TOPLEFT", gp.save, "BOTTOMLEFT", 0, -10)

        gp.curText:SetText(("Current: Renown %d / %d"):format(cur, cap))
    else
        -- Faction (standing) UI  (uses a context-menu button instead of UIDropDown)
        gp.renownSlider:Hide()
        gp.renownValue:SetText("")
        if gp.lowText then gp.lowText:Hide() end
        if gp.highText then gp.highText:Hide() end

        gp.curText:SetText(("Current: %d / %d (Standing %s)"):format(row.current or 0, row.max or 0, tostring(row.standingID or "?")))

        -- build/select button once
        if not gp.standingBtn then
            gp.standingBtn = CreateChoiceButton(gp, 160)
            gp.standingBtn:SetPoint("TOPLEFT", gp.targetLabel, "BOTTOMLEFT", 0, -6)
            gp.standingBtn:SetLabel("Select…")
        end
        gp.standingBtn:Show()
        gp._targetStanding = nil

        -- choices
        local choices = {
            { txt="Friendly", id=5 },
            { txt="Honored",  id=6 },
            { txt="Revered",  id=7 },
            { txt="Exalted",  id=8 },
        }

        -- open modern context menu on click
        gp.standingBtn:SetScript("OnClick", function(btn)
            MenuUtil.CreateContextMenu(btn, function(_, root)
                root:CreateTitle("Target Standing")
                for _, c in ipairs(choices) do
                    root:CreateCheckbox(c.txt, function() return gp._targetStanding == c.id end, function()
                        gp._targetStanding = c.id
                        gp.standingBtn:SetLabel(c.txt)
                    end)
                end
                root:CreateDivider()
                root:CreateButton("Cancel")
            end)
        end)

        -- buttons under the selector
        gp.save:ClearAllPoints()
        gp.save:SetPoint("TOPLEFT", gp.standingBtn, "BOTTOMLEFT", 0, -10)
        gp.clear:ClearAllPoints()
        gp.clear:SetPoint("LEFT", gp.save, "RIGHT", 8, 0)

        gp.taskHeader:ClearAllPoints()
        gp.taskHeader:SetPoint("TOPLEFT", gp.save, "BOTTOMLEFT", 0, -10)

    end


    gp.save:SetScript("OnClick", function()
        if row.type == "renown" then
            local target = math.floor(gp.renownSlider:GetValue())
            self:SetGoal(row.factionID, { type="renown", targetRenown=target })
        else
            if not gp._targetStanding then return end
            self:SetGoal(row.factionID, { type="faction", targetStandingID=gp._targetStanding })
        end
        UI.RefreshGoalTasks(self)
    end)
    gp.clear:SetScript("OnClick", function()
        self:ClearGoal(row.factionID)
        UI.RefreshGoalTasks(self)
    end)

    UI.RefreshGoalTasks(self)
    -- Always re-run skinning in case ElvUI loads late or the panel is new
    self:TrySkinElvUI(self.MainWindow, nil)
end

function UI.RefreshGoalTasks(self)
    if not self.MainWindow or not self.MainWindow._goalPanel then return end
    local gp = self.MainWindow._goalPanel
    local row = gp._row; if not row then return end

    local goal = self:GetGoal(row.factionID)
    if row.type == "renown" then
        if goal and goal.targetRenown then gp.renownSlider:SetValue(goal.targetRenown) end
    else
        if goal and goal.targetStandingID then
            local map = { [5]="Friendly", [6]="Honored", [7]="Revered", [8]="Exalted" }
            if self.MainWindow and self.MainWindow._goalPanel and self.MainWindow._goalPanel.standingBtn then
                self.MainWindow._goalPanel.standingBtn:SetLabel(map[goal.targetStandingID] or "Select…")
            end
            local gp = self.MainWindow._goalPanel
            gp._targetStanding = goal.targetStandingID
        else
            if self.MainWindow and self.MainWindow._goalPanel and self.MainWindow._goalPanel.standingBtn then
                self.MainWindow._goalPanel.standingBtn:SetLabel("Select…")
            end
        end
    end

    local tasks, completed = ns.Goals.GenerateTasks(self.db, row)
    local total = #tasks
    local offset = FauxScrollFrame_GetOffset(gp.scroll) or 0
    FauxScrollFrame_Update(gp.scroll, total, 8, 20)

    for i=1, 8 do
        local idx = offset + i
        local r = gp.rows[i]
        local t = tasks[idx]
        if t then
            r._data = t; r:Show()
            r.name:SetText(t.name or "")
            r.rep:SetText((t.rep or 0) .. " rep")
            r.reset:SetText(t.reset or "")
            r.db = self.db
            r._factionID = row.factionID
            local isDone = completed and t.activityKey and completed[t.activityKey]
            r:SetBackdropColor(isDone and 0.08 or 0, 0.18, isDone and 0.08 or 0, isDone and 0.22 or 0.06)
        else
            r._data = nil
            r:Hide()
        end
    end

    gp.scroll:SetScript("OnVerticalScroll", function(selfScroll, off)
        FauxScrollFrame_OnVerticalScroll(selfScroll, off, 20, function() UI.RefreshGoalTasks(self) end)
    end)
end

-- ===== Updated Row Context Menu =====
function UI.ShowRowContextMenu(self, rowData)
    if not rowData or not rowData.factionID then return end
    local hasGoal = self.GetGoal and (self:GetGoal(rowData.factionID) ~= nil)

    MenuUtil.CreateContextMenu(UI.ContextMenu or UIParent, function(owner, root)
        root:CreateTitle(rowData.name or "Reputation")
        root:CreateButton("Set Goal…", function()
            if self.ShowGoalPanel then self:ShowGoalPanel(rowData) end
        end)
        if hasGoal then
            root:CreateButton("Clear Goal", function()
                if self.ClearGoal then
                    self:ClearGoal(rowData.factionID)
                    if self.MainWindow and self.MainWindow._goalPanel and self.MainWindow._goalPanel:IsShown() then
                        ns.UI.RefreshGoalTasks(self)
                    end
                end
            end)
        end
        root:CreateDivider()
        root:CreateButton("Cancel")
    end)

    -- Apply ElvUI skin if available
    if AddOnLoaded("ElvUI") and ElvUI then
        local E = unpack(ElvUI)
        local S = E:GetModule("Skins", true)
        if S and S.HandleDropDownMenu then
            -- Blizzard names menus "DropDownList1", "DropDownList2", etc.
            local menuFrame = _G["DropDownList1"]
            if menuFrame then
                S:HandleDropDownMenu(menuFrame)
            end
        end
    end
end
