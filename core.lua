-- Path to Exalted (Ace3 + embedded Libs) - WoW 11.2
-- Docs: https://www.townlong-yak.com/framexml/live/Blizzard_APIDocumentation

local ADDON_NAME, ns = ...

--=============================
-- Ace3 Boot
--=============================
local P2E = LibStub("AceAddon-3.0"):NewAddon(
  "PathToExalted",
  "AceConsole-3.0",
  "AceEvent-3.0"
)

local LDB = LibStub("LibDataBroker-1.1", true)
local LDI = LibStub("LibDBIcon-1.0", true)

--=============================
-- DB Defaults
--=============================
local defaults = {
  profile = {
    window  = { x = 200, y = -200, w = 520, h = 440, shown = true, alpha = 1 },
    minimap = { hide = false },
    debug   = false,
  },
  reputations = {},  -- Phase 1 will formalize schema
  goals       = {},  -- Phase 2+
}

--=============================
-- Util
--=============================
local function dprint(self, ...)
  if self and self.db and self.db.profile.debug then
    print("|cff66CDAA[P2E]|r", ...)
  end
end

local function HasRetailRepAPIs()
  return C_Reputation and C_MajorFactions
end

--=============================
-- Lifecycle
--=============================
function P2E:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("PathToExaltedDB", defaults, true)

  -- Broker + Minimap (optional but embedded)
  if LDB then
    self.ldbObject = LDB:NewDataObject("PathToExalted", {
      type = "data source",
      text = "P2E",
      icon = 134400, -- Interface\\Icons\\INV_Misc_Star_01
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

  -- AceConfig: stub options (expand as we add features)
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

  -- Slash
  self:RegisterChatCommand("p2e", function(input)
    input = (input or ""):trim():lower()
    if input == "" or input == "show" then
      self:Toggle()
    elseif input == "scan" then
      self:ScanReputations(true)
    elseif input == "debug" then
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

  self:CreateMainWindow()
  if self.db.profile.window.shown then self.MainWindow:Show() else self.MainWindow:Hide() end

  self:ScanReputations()
end

--=============================
-- Events
--=============================
function P2E:OnPlayerLogin()          self:ScanReputations() end
function P2E:OnPlayerEnteringWorld()  self:ScanReputations() end
function P2E:OnReputationChanged()    self:ScanReputations() end

--=============================
-- UI (ElvUI-aware)
--=============================
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

  -- Default backdrop (removed if ElvUI skins)
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

  local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  msg:SetPoint("TOPLEFT", 16, -40)
  msg:SetJustifyH("LEFT")
  msg:SetText("Ace3 + Libs scaffold loaded.\n/p2e to toggle, /p2e scan to refresh.\nPhase 1: list UI & filters next.")

  self.MainWindow = f
  self:TrySkinElvUI(f, close)
end

function P2E:Toggle()
  if not self.MainWindow then self:CreateMainWindow() end
  local shown = self.MainWindow:IsShown()
  self.db.profile.window.shown = not shown
  if shown then self.MainWindow:Hide() else self.MainWindow:Show() end
end

function P2E:TrySkinElvUI(frame, close)
  if not IsAddOnLoaded("ElvUI") or not ElvUI then return end
  local E = unpack(ElvUI); if not E then return end
  local S = E:GetModule("Skins", true); if not S then return end
  frame:SetBackdrop(nil)
  if S.HandleFrame then S:HandleFrame(frame, true, nil, 10, -10, -10, 10) end
  if S.HandleCloseButton and close then S:HandleCloseButton(close) end
end

--=============================
-- Reputation Scan (Phase 1-ready)
--=============================
function P2E:ScanReputations(verbose)
  local out = {}
  local guid = UnitGUID("player") or "unknown"

  if HasRetailRepAPIs() then
    -- Major Factions (renown)
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
            renownCap  = info.renownLevelCap or info.renownLevel or 0, -- refine later
            isWarband  = true,
          })
        end
      end
    end

    -- Regular factions
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
    elseif GetNumFactions and GetFactionInfo then
      -- Legacy fallback
      local n = GetNumFactions()
      for i = 1, n do
        local name, _, standingID, barMin, barMax, barValue, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
        if name and not isHeader then
          table.insert(out, {
            type = "faction",
            name = name,
            factionID = factionID,
            current = barValue - barMin,
            max     = barMax - barMin,
            standingID = standingID,
            isWarband  = false,
            characterGUID = guid,
          })
        end
      end
    end
  else
    -- Very old client safety
    if GetNumFactions and GetFactionInfo then
      local n = GetNumFactions()
      for i = 1, n do
        local name, _, standingID, barMin, barMax, barValue, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
        if name and not isHeader then
          table.insert(out, {
            type = "faction",
            name = name,
            factionID = factionID,
            current = barValue - barMin,
            max     = barMax - barMin,
            standingID = standingID,
            isWarband  = false,
            characterGUID = guid,
          })
        end
      end
    end
  end

  self.db.reputations = out
  dprint(self, "Scan complete. Entries:", #out)
  if verbose then self:Print(("Scanned %d reputation entries."):format(#out)) end
end
