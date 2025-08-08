-- reputation.lua
-- Data/model: scanning, filtering, sorting, view
local ADDON_NAME, ns = ...
ns.Data = ns.Data or {}

local Data = ns.Data

-- private state
local VIEW = { rows = {} }

-- helpers (shared)
function Data.Pct(cur, maxv)
    cur = tonumber(cur) or 0
    maxv = tonumber(maxv) or 0
    if maxv <= 0 then return 0 end
    local p = math.floor((cur / maxv) * 100 + 0.5)
    if p < 0 then p = 0 end
    if p > 100 then p = 100 end
    return p
end

function Data.HasRetailRepAPIs()
    return C_Reputation and C_MajorFactions
end

-- constants
Data.TYPE_CHOICES   = { "All", "faction", "renown" }
Data.STATUS_CHOICES = { "All", "In-Progress", "Maxed" }
Data.SORT_CHOICES   = { "Progress", "Name" }

local function IsMaxed(row)
    if row.type == "renown" then
        return (row.renownCap or 0) > 0 and (row.renownLevel or 0) >= (row.renownCap or 0)
    else
        return (row.max or 0) > 0 and (row.current or 0) >= (row.max or 0)
    end
end

-- main scanners
function Data.ScanAll(db, dprint)
    local out = {}
    local guid = UnitGUID("player") or "unknown"

    if Data.HasRetailRepAPIs() then
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

    db.global.reputations = out
    if dprint then dprint("Scan complete. Entries:", #out) end
    return #out
end

-- view build + refresh
function Data.BuildView(db, filters)
    wipe(VIEW.rows)
    local tFilter = filters.type or "All"
    local sFilter = filters.status or "All"

    for _, r in ipairs(db.global.reputations or {}) do
        if (tFilter == "All" or r.type == tFilter) then
            local pass = true
            if sFilter == "Maxed" then
                pass = IsMaxed(r)
            elseif sFilter == "In-Progress" then
                pass = not IsMaxed(r)
            end
            if pass then table.insert(VIEW.rows, r) end
        end
    end

    local sortBy = filters.sort or "Progress"
    if sortBy == "Name" then
        table.sort(VIEW.rows, function(a,b) return (a.name or "") < (b.name or "") end)
    else
        table.sort(VIEW.rows, function(a,b)
            local ap = (a.type == "renown") and Data.Pct(a.renownLevel or 0, a.renownCap or 0) or Data.Pct(a.current or 0, a.max or 0)
            local bp = (b.type == "renown") and Data.Pct(b.renownLevel or 0, b.renownCap or 0) or Data.Pct(b.current or 0, b.max or 0)
            if ap == bp then return (a.name or "") < (b.name or "") end
            return ap > bp
        end)
    end
end

function Data.GetRows()
    return VIEW.rows
end
