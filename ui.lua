-- ui.lua
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
    filters:SetHeight(56)

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
    typeDrop:SetPoint("LEFT", typeLabel, "RIGHT", -6, -4); UIDropDownMenu_SetWidth(typeDrop, 120)

    local statusLabel = NewLabel(row1, "Status:"); statusLabel:SetPoint("LEFT", typeDrop, "RIGHT", 20, 4)
    local statusDrop = CreateFrame("Frame", "P2E_StatusDropdown", row1, "UIDropDownMenuTemplate")
    statusDrop:SetPoint("LEFT", statusLabel, "RIGHT", -6, -4); UIDropDownMenu_SetWidth(statusDrop, 140)

    local row2 = CreateFrame("Frame", nil, filters); row2:SetHeight(26)
    row2:SetPoint("TOPLEFT", row1, "BOTTOMLEFT", 0, -4)
    row2:SetPoint("TOPRIGHT", row1, "BOTTOMRIGHT", 0, -4)

    local sortLabel = NewLabel(row2, "Sort:"); sortLabel:SetPoint("LEFT", row2, "LEFT", 0, 0)
    local sortDrop = CreateFrame("Frame", "P2E_SortDropdown", row2, "UIDropDownMenuTemplate")
    sortDrop:SetPoint("LEFT", sortLabel, "RIGHT", -6, -4); UIDropDownMenu_SetWidth(sortDrop, 140)

    f.filters = { typeDrop = typeDrop, statusDrop = statusDrop, sortDrop = sortDrop }

    -- header
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -6)
    header:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    header:SetHeight(22)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    header:SetBackdropColor(0,0,0,0.2)
    header:SetBackdropBorderColor(0,0,0,0.4)

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
        return row
    end

    for i = 1, MAX_ROWS do f.rows[i] = CreateRow(i) end

    f.scroll = scroll
    self.MainWindow = f

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
    local Data = ns.Data

    UIDropDownMenu_Initialize(f.filters.typeDrop, function(_, level)
        if level ~= 1 then return end
        for _, v in ipairs({ "All", "faction", "renown" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.func = function() filters.type = v; _DD_SetText(f.filters.typeDrop, v); self:RefreshView() end
            info.checked = (filters.type == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end); _DD_SetText(f.filters.typeDrop, filters.type or "All")

    UIDropDownMenu_Initialize(f.filters.statusDrop, function(_, level)
        if level ~= 1 then return end
        for _, v in ipairs({ "All", "In-Progress", "Maxed" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.func = function() filters.status = v; _DD_SetText(f.filters.statusDrop, v); self:RefreshView() end
            info.checked = (filters.status == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end); _DD_SetText(f.filters.statusDrop, filters.status or "All")

    UIDropDownMenu_Initialize(f.filters.sortDrop, function(_, level)
        if level ~= 1 then return end
        for _, v in ipairs({ "Progress", "Name" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.func = function() filters.sort = v; _DD_SetText(f.filters.sortDrop, v); self:RefreshView() end
            info.checked = (filters.sort == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end); _DD_SetText(f.filters.sortDrop, filters.sort or "Progress")
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
    if not IsAddOnLoaded or not IsAddOnLoaded("ElvUI") or not ElvUI then return end
    local E = unpack(ElvUI); if not E then return end
    local S = E:GetModule("Skins", true); if not S then return end
    frame:SetBackdrop(nil)
    if S.HandleFrame then S:HandleFrame(frame, true, nil, 10, -10, -10, 10) end
    if S.HandleCloseButton and close then S:HandleCloseButton(close) end
end
