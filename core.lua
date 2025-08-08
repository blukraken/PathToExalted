-- Path to Exalted (Ace3 + embedded Libs) - Phase 1 UI
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
local AceGUI = LibStub("AceGUI-3.0")

--=============================
-- DB Defaults
--=============================
local defaults = {
  profile = {
    window  = { x = 200, y = -200, w = 560, h = 520, shown = true, alpha = 1 },
    minimap = { hide = false },
    debug   = false,

    -- UI state
    filters = {
      type   = "All",      -- All | Faction | Renown
      status = "All",      -- All | In Progress | Maxed
      sort   = "Progress", -- Progress | Name
    },
  },
  reputations = {},  -- Phase 1 snapshot store
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

local function HasRetailRepAPIs() return C_Reputation and C_MajorFactions end

-- Progress helpers
local function entryIsMaxed(e)
  if e.type == "renown" then
    if e.renownCap and e.renownCap > 0 then
      return (e.renownLevel or 0) >= e.renownCap
    end
    return false
  else
    return (e.current or 0) >= (e.max or 1)
  end
end

local function entryProgress(e)
  if e.type == "renown" then
    local cur = e.renownLevel or 0
    local cap = e.renownCap or math.max(cur, 1)
    return cur, cap
  else
    local cur = e.current or 0
    local cap = e.max or 1
    cur = math.max(0, math.min(cur, cap))
    return cur, cap
  end
end

--=============================
-- Lifecycle
--=============================
function P2E:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("PathToExaltedDB", defaults, true)

  -- Broker + Minimap
  if LDB then
    self.ldbObject = LDB:NewDataObject("PathToExalted", {
      type = "data source",
      text = "P2E",
      icon = 134400, -- INV_Misc_Star_01
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

  -- AceConfig (stub)
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
local ROW_HEIGHT   = 30
local ROWS_VISIBLE = 12
local LIST_TOP_Y   = -92
local LIST_LEFT_X  = 16
local LIST_RIGHT_X = -32
local LIST_BOTTOM_Y= 16

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

  -- Default backdrop (ElvUI will reskin)
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

  -- Filter Bar: AceGUI widgets parented into our frame
  f._ace = f._ace or {}
  local function createDropdown(key, label, items, x)
    local dd = AceGUI:Create("Dropdown")
    dd:SetLabel(label)
    dd:SetList(items)
    dd:SetValue(self.db.profile.filters[key])
    dd:SetCallback("OnValueChanged", function(_, _, val)
      self.db.profile.filters[key] = val
      self:RefreshList()
    end)
    dd.frame:SetParent(f)
    dd.frame:SetPoint("TOPLEFT", f, "TOPLEFT", x, -46)
    dd.frame:SetWidth(160)
    f._ace[#f._ace+1] = dd
    return dd
  end

  local typeDD = createDropdown("type", "Type", { All="All", Faction="Faction", Renown="Renown" }, 16)
  local statusDD = createDropdown("status", "Status", { All="All", ["In Progress"]="In Progress", Maxed="Maxed" }, 192)
  local sortDD = createDropdown("sort", "Sort", { Progress="Progress", Name="Name" }, 368)

  -- Rescan button
  local scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scanBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -52)
  scanBtn:SetSize(96, 22)
  scanBtn:SetText("Rescan")
  scanBtn:SetScript("OnClick", function() self:ScanReputations(true) end)

  -- List: ScrollFrame with manual row pool
  local sf = CreateFrame("ScrollFrame", "P2E_ListScroll", f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_LEFT_X, -90)
  sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", LIST_RIGHT_X, LIST_BOTTOM_Y)

  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(1, 1)
  sf:SetScrollChild(content)

  -- Row creation
  local rows = {}
  local function createRow(i)
    local row = CreateFrame("Button", nil, content)
    row:SetSize(1, ROW_HEIGHT)
    if i == 1 then
      row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    else
      row:SetPoint("TOPLEFT", rows[i-1], "BOTTOMLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", rows[i-1], "BOTTOMRIGHT", 0, 0)
    end

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0,0,0,0.25)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetText("Faction Name")

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.value:SetText("0 / 0")

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("LEFT", row, "LEFT", 180, 0)
    row.bar:SetPoint("RIGHT", row, "RIGHT", -120, 0)
    row.bar:SetHeight(12)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetMinMaxValues(0,1)
    row.bar:SetValue(0.0)

    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints()
    row.bar.bg:SetColorTexture(0,0,0,0.4)

    row.bar.text = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bar.text:SetPoint("CENTER", row.bar, "CENTER", 0, 0)
    row.bar.text:SetText("")

    row.SetData = function(r, e)
      r.entry = e
      if e.type == "renown" then
        local cur, cap = entryProgress(e)
        r.name:SetText(("|cffffe066%s|r (Renown)"):format(e.name or ""))
        r.value:SetText(("%d / %d"):format(cur, cap))
        r.bar:SetMinMaxValues(0, cap)
        r.bar:SetValue(cur)
        r.bar.text:SetText(("Renown %d"):format(cur))
      else
        local cur, cap = entryProgress(e)
        r.name:SetText(e.name or "")
        r.value:SetText(("%d / %d"):format(cur, cap))
        r.bar:SetMinMaxValues(0, cap)
        r.bar:SetValue(cur)
        local pct = cap > 0 and math.floor((cur/cap)*100) or 0
        r.bar.text:SetText(("%d%%"):format(pct))
      end

      if entryIsMaxed(e) then
        r.bar:SetStatusBarColor(0.2, 0.8, 0.2)
      else
        r.bar:SetStatusBarColor(0.2, 0.6, 1.0)
      end
    end

    rows[i] = row
  end

  -- Initialize a reasonable number of rows and extend content height as needed
  local MAX_ROWS = 100 -- enough; we only show what we need
  for i=1, MAX_ROWS do createRow(i) end
  content:SetHeight(MAX_ROWS * ROW_HEIGHT)

  -- Store refs
  f.ScrollFrame = sf
  f.Content     = content
  f.Rows        = rows
  f.ScanButton  = scanBtn
  f.Filters     = {
    typeDD   = typeDD,
    statusDD = statusDD,
    sortDD   = sortDD,
  }

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
-- Reputation Scan (Phase 1)
--=============================
function P2E:ScanReputations(verbose)
  local out = {}
  local guid = UnitGUID("player") or "unknown"

  if HasRetailRepAPIs() then
    -- Major Factions (Renown)
    local ids = C_MajorFactions.GetMajorFactionIDs and C_MajorFactions.GetMajorFactionIDs()
    if ids then
      for _, id in ipairs(ids) do
        local info = C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(id)
        if info and info.name then
          table.insert(out, {
            type = "renown",
            name = info.name,
            factionID = id,
            renownLevel = info.renownLevel or 0,
            renownCap  = info.renownLevelCap or info.renownLevel or 0, -- refine later if API provides max properly
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
        if finfo and not finfo.isHeader and finfo.name then
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

  self:RefreshList()
  -- Optional: update LDB text with a tiny summary
  if self.ldbObject then
    local goals = self.db.goals and (next(self.db.goals) and "Goals" or "P2E")
    self.ldbObject.text = goals
  end
end

--=============================
-- Filtering + Sorting + List Refresh
--=============================
local function applyFilters(filters, data)
  local out = {}
  for _, e in ipairs(data) do
    -- Type filter
    if filters.type == "Faction" and e.type ~= "faction" then goto continue end
    if filters.type == "Renown" and e.type ~= "renown" then goto continue end

    -- Status filter
    if filters.status == "Maxed" and not entryIsMaxed(e) then goto continue end
    if filters.status == "In Progress" and entryIsMaxed(e) then goto continue end

    table.insert(out, e)
    ::continue::
  end
  -- Sort
  if filters.sort == "Name" then
    table.sort(out, function(a,b) return (a.name or "") < (b.name or "") end)
  else -- Progress
    table.sort(out, function(a,b)
      local ac, am = entryProgress(a)
      local bc, bm = entryProgress(b)
      local ap = (am > 0) and (ac / am) or 0
      local bp = (bm > 0) and (bc / bm) or 0
      if ap == bp then
        return (a.name or "") < (b.name or "")
      else
        return ap > bp
      end
    end)
  end
  return out
end

function P2E:RefreshList()
  if not self.MainWindow or not self.MainWindow.Rows then return end
  local rows = self.MainWindow.Rows
  local data = self.db.reputations or {}
  local filters = self.db.profile.filters or defaults.profile.filters

  -- Filter + sort snapshot
  self._view = applyFilters(filters, data)
  local view = self._view

  -- Ensure content height fits
  local needed = math.max(#view * ROW_HEIGHT, ROW_HEIGHT)
  self.MainWindow.Content:SetHeight(needed)

  -- Scroll offset -> how many rows above current scroll
  local sf = self.MainWindow.ScrollFrame
  local offset = math.floor((sf:GetVerticalScroll() or 0) / ROW_HEIGHT + 0.5)
  if offset < 0 then offset = 0 end

  -- Update visible rows within the content; we precreated many rows, so hide extras
  local first = offset + 1
  local last  = math.min(offset + math.floor((sf:GetHeight() or 0)/ROW_HEIGHT) + 1, #rows)

  local y = 0
  for i=1, #rows do
    local idx = i + offset
    local row = rows[i]
    if idx <= #view then
      row:SetPoint("TOPLEFT", self.MainWindow.Content, "TOPLEFT", 0, -((i-1)*ROW_HEIGHT))
      row:SetPoint("TOPRIGHT", self.MainWindow.Content, "TOPRIGHT", 0, -((i-1)*ROW_HEIGHT))
      row:SetHeight(ROW_HEIGHT)
      row:SetData(view[idx])
      row:Show()
      y = y + ROW_HEIGHT
    else
      row:Hide()
    end
  end
end

-- Keep list in sync with scroll
hooksecurefunc(UIPanelScrollFrameTemplateMixin or {}, "OnVerticalScroll", function() end) -- noop guard
-- Simple handler: when the scrollframe scrolls, refresh which rows show
-- (We can't hook the mixin easily; instead we set OnVerticalScroll directly.)
-- Do this after window is created:
C_Timer.After(0.5, function()
  if P2E.MainWindow and P2E.MainWindow.ScrollFrame then
    P2E.MainWindow.ScrollFrame:SetScript("OnVerticalScroll", function(self, delta)
      local current = self:GetVerticalScroll()
      local new = math.max(0, current + (delta or 0))
      self:SetVerticalScroll(new)
      if P2E.RefreshList then P2E:RefreshList() end
    end)
  end
end)
