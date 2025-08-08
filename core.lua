-- Path to Exalted (Ace3 + embedded Libs) - WoW 11.2
-- Author: Cameron
-- Phase 1: Main window + scroll list + filters (Type/Status/Sort)

local ADDON_NAME, ns = ...

------------------------------------------------
-- Lua 5.1 safe utils
------------------------------------------------
local function trim(s) return (s and s:match("^%s*(.-)%s*$")) or "" end

-- Safe IsAddonLoaded wrapper for 11.x
local function IsAddonLoaded(addon)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(addon) and true or false
    elseif _G.IsAddOnLoaded then
        return _G.IsAddOnLoaded(addon) and true or false
    end
    return false
end

local function dprint(self, ...)
    if self and self.db and self.db.profile.debug then
        print("|cff66CDAA[P2E]|r", ...)
    end
end

local function HasRetailRepAPIs()
    return C_Reputation and C_MajorFactions
end

------------------------------------------------
-- Ace3 boot
------------------------------------------------
local P2E = LibStub("AceAddon-3.0"):NewAddon(
    "PathToExalted",
    "AceConsole-3.0",
    "AceEvent-3.0"
)

local LDB = LibStub("LibDataBroker-1.1", true)
local LDI = LibStub("LibDBIcon-1.0", true)

------------------------------------------------
-- SavedVariables defaults
------------------------------------------------
local defaults = {
    profile = {
        window  = { x = 200, y = -200, w = 640, h = 520, shown = true, alpha = 1 },
        minimap = { hide = false },
        debug   = false,
        filters = { type="All", status="All", sort="Progress" },
    },
    global = {
        reputations = {}, -- raw scan output (all)
    },
}

------------------------------------------------
-- Local state (derived/filtered view)
------------------------------------------------
local VIEW = {
    rows = {},   -- filtered/sorted rows for display
}

------------------------------------------------
-- Lifecycle
------------------------------------------------
function P2E:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("PathToExaltedDB", defaults, true)

    -- LDB object
    if LDB then
        self.ldbObject = LDB:NewDataObject("PathToExalted", {
            type = "data source",
            text = "P2E",
            icon = 134400, -- generic banner icon
            OnClick = function(_, btn)
                if btn == "LeftButton" then self:Toggle() end
                if btn == "RightButton" then InterfaceOptionsFrame_OpenToCategory("Path to Exalted") end
            end,
            OnTooltipShow = function(tt)
                tt:AddLine("Path to Exalted")
                tt:AddLine("|cffffffffLeft-Click|r toggle")
                tt:AddLine("|cffffffffRight-Click|r options")
            end,
        })
        if LDI then
            LDI:Register("PathToExalted", self.ldbObject, self.db.profile.minimap)
            if not self.db.profile.minimap.hide then LDI:Show("PathToExalted") end
        end
    end

    -- Options panel
    local AceConfig = LibStub("AceConfig-3.0", true)
    local AceDialog = LibStub("AceConfigDialog-3.0", true)
    if AceConfig and AceDialog then
        local opts = {
            type = "group",
            name = "Path to Exalted",
            args = {
                show = {
                    type = "execute", name = "Show/Hide", order = 1,
                    func = function() self:Toggle() end,
                },
                minimap = {
                    type = "toggle", name = "Show minimap button", order = 2,
                    get = function() return not self.db.profile.minimap.hide end,
                    set = function(_, v)
                        self.db.profile.minimap.hide = not v
                        if LDI then
                            if v then LDI:Show("PathToExalted") else LDI:Hide("PathToExalted") end
                        end
                    end,
                },
                alpha = {
                    type = "range", name = "Window opacity", order = 3,
                    min = 0.4, max = 1.0, step = 0.05,
                    get = function() return self.db.profile.window.alpha end,
                    set = function(_, val)
                        self.db.profile.window.alpha = val
                        if self.MainWindow then self.MainWindow:SetAlpha(val) end
                    end,
                },
                debug = {
                    type = "toggle", name = "Enable debug prints", order = 4,
                    get = function() return self.db.profile.debug end,
                    set = function(_, v) self.db.profile.debug = v end,
                },
            },
        }
        AceConfig:RegisterOptionsTable("Path to Exalted", opts)
        AceDialog:AddToBlizOptions("Path to Exalted")
    end

    -- Slash command
    self:RegisterChatCommand("p2e", function(input)
        local cmd = string.lower(trim(input or ""))
        if cmd == "" or cmd == "show" then
            self:Toggle()
        elseif cmd == "scan" then
            self:ScanReputations(true)
            self:RefreshView()
        elseif cmd == "debug" then
            self.db.profile.debug = not self.db.profile.debug
            self:Print("Debug:", self.db.profile.debug and "ON" or "OFF")
        else
            self:Print("Commands: /p2e [show|scan|debug]")
        end
    end)
end

function P2E:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("UPDATE_FACTION", "OnReputationChanged")

    if self.db.profile.window.shown then
        self:CreateMainWindow()
    end
    self:ScanReputations()
    self:RefreshView()
end

------------------------------------------------
-- Event handlers
------------------------------------------------
function P2E:OnPlayerLogin()          self:ScanReputations(); self:RefreshView() end
function P2E:OnPlayerEnteringWorld()  self:ScanReputations(); self:RefreshView() end
function P2E:OnReputationChanged()    self:ScanReputations(); self:RefreshView() end

------------------------------------------------
-- UI helpers
------------------------------------------------
local ROW_HEIGHT = 22
local MAX_ROWS   = 16  -- fits 520px tall with header/filters

local function pct(cur, maxv)
    cur = tonumber(cur) or 0
    maxv = tonumber(maxv) or 0
    if maxv <= 0 then return 0 end
    local p = math.floor((cur / maxv) * 100 + 0.5)
    if p < 0 then p = 0 end
    if p > 100 then p = 100 end
    return p
end

------------------------------------------------
-- Main Window + Controls + Scroll List
------------------------------------------------
function P2E:CreateMainWindow()
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

    -- Filters line
    local filters = CreateFrame("Frame", nil, f)
    filters:SetPoint("TOPLEFT", 12, -40)
    filters:SetSize(cfg.w - 24, 26)

    local function NewLabel(parent, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetText(text)
        return fs
    end

    -- Type dropdown
    local typeLabel = NewLabel(filters, "Type:")
    typeLabel:SetPoint("LEFT", filters, "LEFT", 0, 0)

    local typeDrop = CreateFrame("Frame", "P2E_TypeDropdown", filters, "UIDropDownMenuTemplate")
    typeDrop:SetPoint("LEFT", typeLabel, "RIGHT", -6, -4)

    -- Status dropdown
    local statusLabel = NewLabel(filters, "Status:")
    statusLabel:SetPoint("LEFT", typeDrop, "RIGHT", 80, 4)

    local statusDrop = CreateFrame("Frame", "P2E_StatusDropdown", filters, "UIDropDownMenuTemplate")
    statusDrop:SetPoint("LEFT", statusLabel, "RIGHT", -6, -4)

    -- Sort dropdown
    local sortLabel = NewLabel(filters, "Sort:")
    sortLabel:SetPoint("LEFT", statusDrop, "RIGHT", 80, 4)

    local sortDrop = CreateFrame("Frame", "P2E_SortDropdown", filters, "UIDropDownMenuTemplate")
    sortDrop:SetPoint("LEFT", sortLabel, "RIGHT", -6, -4)

    -- Scan button
    local scanBtn = CreateFrame("Button", nil, filters, "UIPanelButtonTemplate")
    scanBtn:SetText("Scan")
    scanBtn:SetSize(80, 22)
    scanBtn:SetPoint("RIGHT", filters, "RIGHT", 0, 0)
    scanBtn:SetScript("OnClick", function()
        self:ScanReputations(true)
        self:RefreshView()
    end)

    -- Header row
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
        fs:SetText(text)
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", parent, point or "LEFT", xOff or 0, 0)
        fs:SetWidth(w)
        return fs
    end

    -- Column widths
    local COLW_NAME   = 230
    local COLW_TYPE   = 70
    local COLW_LEVEL  = 110
    local COLW_PROG   = 80
    local COLW_EXTRA  = 100 -- renown cap / standing

    local hName  = NewHeaderText(header, "Name",  COLW_NAME, "LEFT", 6)
    local hType  = NewHeaderText(header, "Type",  COLW_TYPE, "LEFT", 12 + COLW_NAME)
    local hLevel = NewHeaderText(header, "Level", COLW_LEVEL, "LEFT", 18 + COLW_NAME + COLW_TYPE)
    local hProg  = NewHeaderText(header, "Progress", COLW_PROG, "LEFT", 24 + COLW_NAME + COLW_TYPE + COLW_LEVEL)
    local hExtra = NewHeaderText(header, "Details", COLW_EXTRA, "LEFT", 30 + COLW_NAME + COLW_TYPE + COLW_LEVEL + COLW_PROG)

    -- Scroll area
    local scroll = CreateFrame("ScrollFrame", "P2E_ScrollFrame", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 12)

    -- Row factory
    f.rows = {}
    local function CreateRow(index)
        local row = CreateFrame("Button", nil, f, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", f, "LEFT", 12, 0)
        row:SetPoint("RIGHT", f, "RIGHT", -12, 0)

        if index == 1 then
            row:SetPoint("TOP", scroll, "TOP", 0, 0)
        else
            row:SetPoint("TOP", f.rows[index-1], "BOTTOM", 0, -2)
        end

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

        row.name:SetPoint("LEFT", row, "LEFT", 6, 0);                      row.name:SetWidth(COLW_NAME);  row.name:SetJustifyH("LEFT")
        row.type:SetPoint("LEFT", row, "LEFT", 12 + COLW_NAME, 0);         row.type:SetWidth(COLW_TYPE);  row.type:SetJustifyH("LEFT")
        row.level:SetPoint("LEFT", row, "LEFT", 18 + COLW_NAME + COLW_TYPE, 0); row.level:SetWidth(COLW_LEVEL); row.level:SetJustifyH("LEFT")
        row.prog:SetPoint("LEFT", row, "LEFT", 24 + COLW_NAME + COLW_TYPE + COLW_LEVEL, 0); row.prog:SetWidth(COLW_PROG); row.prog:SetJustifyH("LEFT")
        row.extra:SetPoint("LEFT", row, "LEFT", 30 + COLW_NAME + COLW_TYPE + COLW_LEVEL + COLW_PROG, 0); row.extra:SetWidth(COLW_EXTRA); row.extra:SetJustifyH("LEFT")

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

    for i = 1, MAX_ROWS do
        f.rows[i] = CreateRow(i)
    end

    -- Save refs
    f.filters = { typeDrop = typeDrop, statusDrop = statusDrop, sortDrop = sortDrop }
    f.scroll  = scroll
    self.MainWindow = f

    -- Dropdown init
    self:InitDropdowns()

    -- Scroll update hook
    scroll:SetScript("OnVerticalScroll", function(selfScroll, offset)
        FauxScrollFrame_OnVerticalScroll(selfScroll, offset, ROW_HEIGHT + 2, function() P2E:RefreshRows() end)
    end)

    -- Initial paint
    self:TrySkinElvUI(f, close)
    self:RefreshRows()
end

function P2E:Toggle()
    if not self.MainWindow then self:CreateMainWindow() end
    local shown = self.MainWindow:IsShown()
    self.db.profile.window.shown = not shown
    if shown then self.MainWindow:Hide() else self.MainWindow:Show() end
end

function P2E:TrySkinElvUI(frame, close)
    if not IsAddonLoaded("ElvUI") or not ElvUI then return end
    local E = unpack(ElvUI); if not E then return end
    local S = E:GetModule("Skins", true); if not S then return end
    frame:SetBackdrop(nil)
    if S.HandleFrame then S:HandleFrame(frame, true, nil, 10, -10, -10, 10) end
    if S.HandleCloseButton and close then S:HandleCloseButton(close) end
end

------------------------------------------------
-- Reputation Scan
------------------------------------------------
function P2E:ScanReputations(verbose)
    local out = {}
    local guid = UnitGUID("player") or "unknown"

    if HasRetailRepAPIs() then
        local ids = C_MajorFactions.GetMajorFactionIDs and C_MajorFactions.GetMajorFactionIDs()
        if ids then
            for _, id in ipairs(ids) do
                local info = C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(id)
                if info then
                    table.insert(out, {
                        type = "renown",
                        name = info.name,
                        factionID = id,
                        renownLevel = info.renownLevel or 0,
                        renownCap  = info.renownLevelCap or info.renownLevel or 0,
                        isWarband  = true,
                    })
                end
            end
        end
        if C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
            local n = C_Reputation.GetNumFactions()
            for i = 1, n do
                local finfo = C_Reputation.GetFactionDataByIndex(i)
                if finfo and not finfo.isHeader then
                    table.insert(out, {
                        type = "faction",
                        name = finfo.name,
                        factionID = finfo.factionID,
                        current = finfo.currentStanding or 0,
                        max     = finfo.maxStanding or 42000,
                        standingID = finfo.standingID,
                        isWarband  = false,
                        characterGUID = guid,
                    })
                end
            end
        end
    elseif GetNumFactions and GetFactionInfo then
        local n = GetNumFactions()
        for i = 1, n do
            local name, _, standingID, barMin, barMax, barValue, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
            if name and not isHeader then
                table.insert(out, {
                    type = "faction",
                    name = name,
                    factionID = factionID,
                    current = (barValue or 0) - (barMin or 0),
                    max     = (barMax or 0) - (barMin or 0),
                    standingID = standingID,
                    isWarband  = false,
                    characterGUID = guid,
                })
            end
        end
    end

    self.db.global.reputations = out
    dprint(self, "Scan complete. Entries:", #out)
    if verbose then self:Print(("Scanned %d reputation entries."):format(#out)) end
end

------------------------------------------------
-- Filtering / Sorting / View
------------------------------------------------
local TYPE_CHOICES   = { "All", "faction", "renown" }
local STATUS_CHOICES = { "All", "In-Progress", "Maxed" }
local SORT_CHOICES   = { "Progress", "Name" }

local function isMaxed(row)
    if row.type == "renown" then
        return (row.renownCap or 0) > 0 and (row.renownLevel or 0) >= (row.renownCap or 0)
    else
        return (row.max or 0) > 0 and (row.current or 0) >= (row.max or 0)
    end
end

function P2E:BuildFilteredRows()
    local filters = self.db.profile.filters
    local tFilter = filters.type or "All"
    local sFilter = filters.status or "All"

    wipe(VIEW.rows)
    for _, r in ipairs(self.db.global.reputations or {}) do
        if (tFilter == "All" or r.type == tFilter) then
            local pass = true
            if sFilter == "Maxed" then
                pass = isMaxed(r)
            elseif sFilter == "In-Progress" then
                pass = not isMaxed(r)
            end
            if pass then
                table.insert(VIEW.rows, r)
            end
        end
    end

    -- Sort
    local sortBy = filters.sort or "Progress"
    if sortBy == "Name" then
        table.sort(VIEW.rows, function(a,b)
            return (a.name or "") < (b.name or "")
        end)
    else
        -- Progress descending
        table.sort(VIEW.rows, function(a,b)
            local ap, bp
            if a.type == "renown" then ap = pct(a.renownLevel or 0, a.renownCap or 0) else ap = pct(a.current or 0, a.max or 0) end
            if b.type == "renown" then bp = pct(b.renownLevel or 0, b.renownCap or 0) else bp = pct(b.current or 0, b.max or 0) end
            if ap == bp then
                return (a.name or "") < (b.name or "")
            end
            return ap > bp
        end)
    end
end

function P2E:RefreshView()
    self:BuildFilteredRows()
    self:RefreshRows()
end

function P2E:RefreshRows()
    if not self.MainWindow then return end
    local scroll = self.MainWindow.scroll
    local total = #VIEW.rows

    local offset = FauxScrollFrame_GetOffset(scroll) or 0
    FauxScrollFrame_Update(scroll, total, MAX_ROWS, ROW_HEIGHT + 2)

    for i = 1, MAX_ROWS do
        local idx = i + offset
        local row = self.MainWindow.rows[i]
        local r = VIEW.rows[idx]

        if r then
            row._data = r
            row:Show()

            row.name:SetText(r.name or "?")
            row.type:SetText(r.type == "renown" and "Renown" or "Faction")

            if r.type == "renown" then
                local cur, cap = r.renownLevel or 0, r.renownCap or 0
                row.level:SetText(("%d / %d"):format(cur, cap))
                row.prog:SetText(("%d%%"):format(pct(cur, cap)))
                row.extra:SetText(r.isWarband and "Warband" or "")
            else
                local cur, maxv = r.current or 0, r.max or 0
                row.level:SetText(("%d / %d"):format(cur, maxv))
                row.prog:SetText(("%d%%"):format(pct(cur, maxv)))
                row.extra:SetText(("Standing %s"):format(tostring(r.standingID or "?")))
            end

            -- subtle visual cue when maxed
            if isMaxed(r) then
                row:SetBackdropColor(0.08, 0.18, 0.08, 0.20)
            else
                row:SetBackdropColor(0,0,0,0.05)
            end
        else
            row._data = nil
            row:Hide()
        end
    end
end

------------------------------------------------
-- Dropdowns
------------------------------------------------
local function _DD_SetText(drop, text)
    -- Helper because UIDropDownMenu_SetText is protected in some templates
    local fs = _G[drop:GetName().."Text"]
    if fs then fs:SetText(text) end
end

function P2E:InitDropdowns()
    if not self.MainWindow then return end
    local f = self.MainWindow
    local filters = self.db.profile.filters

    -- Type
    UIDropDownMenu_Initialize(f.filters.typeDrop, function(selfDD, level)
        if level ~= 1 then return end
        for _, v in ipairs(TYPE_CHOICES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.func = function()
                filters.type = v
                _DD_SetText(f.filters.typeDrop, v)
                P2E:RefreshView()
            end
            info.checked = (filters.type == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetWidth(f.filters.typeDrop, 110)
    _DD_SetText(f.filters.typeDrop, filters.type or "All")

    -- Status
    UIDropDownMenu_Initialize(f.filters.statusDrop, function(selfDD, level)
        if level ~= 1 then return end
        for _, v in ipairs(STATUS_CHOICES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.func = function()
                filters.status = v
                _DD_SetText(f.filters.statusDrop, v)
                P2E:RefreshView()
            end
            info.checked = (filters.status == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetWidth(f.filters.statusDrop, 130)
    _DD_SetText(f.filters.statusDrop, filters.status or "All")

    -- Sort
    UIDropDownMenu_Initialize(f.filters.sortDrop, function(selfDD, level)
        if level ~= 1 then return end
        for _, v in ipairs(SORT_CHOICES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.func = function()
                filters.sort = v
                _DD_SetText(f.filters.sortDrop, v)
                P2E:RefreshView()
            end
            info.checked = (filters.sort == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetWidth(f.filters.sortDrop, 120)
    _DD_SetText(f.filters.sortDrop, filters.sort or "Progress")
end
