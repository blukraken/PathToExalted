-- PathToExalted.lua
-- Core boot + options + events + orchestration
local ADDON_NAME, ns = ...

local function trim(s) return (s and s:match("^%s*(.-)%s*$")) or "" end

local P2E = LibStub("AceAddon-3.0"):NewAddon("PathToExalted", "AceConsole-3.0", "AceEvent-3.0")
ns.Data = ns.Data or {}
ns.UI   = ns.UI   or {}

local LDB = LibStub("LibDataBroker-1.1", true)
local LDI = LibStub("LibDBIcon-1.0", true)

-- SavedVariables
local defaults = {
    profile = {
        window  = { x = 200, y = -200, w = 640, h = 520, shown = true, alpha = 1 },
        minimap = { hide = false },
        debug   = false,
        filters = { type="All", status="All", sort="Progress" },
    },
    global = { reputations = {} },
}

-- debug helper
local function dprint(self, ...)
    if self and self.db and self.db.profile.debug then
        print("|cff66CDAA[P2E]|r", ...)
    end
end

-- === Lifecycle ===
function P2E:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("PathToExaltedDB", defaults, true)

    -- Wire module methods to keep your old self:Method() calls working
    -- Data
    self.ScanReputations = function(_, verbose)
        local n = ns.Data.ScanAll(self.db, function(...) dprint(self, ...) end)
        if verbose then self:Print(("Scanned %d reputation entries."):format(n)) end
    end
    self.BuildFilteredRows = function(_) ns.Data.BuildView(self.db, self.db.profile.filters) end
    self.RefreshView = function(_)
        ns.Data.BuildView(self.db, self.db.profile.filters)
        self:RefreshRows()
    end
    -- UI
    self.CreateMainWindow = function(_) ns.UI.CreateMainWindow(self) end
    self.InitDropdowns    = function(_) ns.UI.InitDropdowns(self) end
    self.RefreshRows      = function(_) ns.UI.RefreshRows(self) end
    self.TrySkinElvUI     = function(_, frame, close) ns.UI.TrySkinElvUI(self, frame, close) end

    -- LDB / Minimap
    if LDB then
        self.ldbObject = LDB:NewDataObject("PathToExalted", {
            type = "data source",
            text = "P2E",
            icon = 134400,
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

    -- Options
    local AceConfig = LibStub("AceConfig-3.0", true)
    local AceDialog = LibStub("AceConfigDialog-3.0", true)
    if AceConfig and AceDialog then
        local opts = {
            type = "group",
            name = "Path to Exalted",
            args = {
                show = { type = "execute", name = "Show/Hide", order = 1, func = function() self:Toggle() end },
                minimap = {
                    type = "toggle", name = "Show minimap button", order = 2,
                    get = function() return not self.db.profile.minimap.hide end,
                    set = function(_, v)
                        self.db.profile.minimap.hide = not v
                        if LDI then if v then LDI:Show("PathToExalted") else LDI:Hide("PathToExalted") end end
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

    -- Slash
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
    self:RegisterEvent("PLAYER_LOGIN",          "OnPlayerLogin")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("UPDATE_FACTION",        "OnReputationChanged")

    if self.db.profile.window.shown then
        self:CreateMainWindow()
    end
    self:ScanReputations()
    self:RefreshView()
end

-- Events just orchestrate data + view
function P2E:OnPlayerLogin()         self:ScanReputations(); self:RefreshView() end
function P2E:OnPlayerEnteringWorld() self:ScanReputations(); self:RefreshView() end
function P2E:OnReputationChanged()   self:ScanReputations(); self:RefreshView() end

function P2E:Toggle()
    if not self.MainWindow then
        self:CreateMainWindow()
        self.MainWindow:Show()
        self.db.profile.window.shown = true
        return
    end
    local shown = self.MainWindow:IsShown()
    self.db.profile.window.shown = not shown
    if shown then self.MainWindow:Hide() else self.MainWindow:Show() end
end
