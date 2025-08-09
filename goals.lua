-- goals.lua
-- Renown task gen is strict: scan ONLY mapped home zones per renown. No mapping => no dynamic WQs.
local ADDON_NAME, ns = ...
ns.Goals = ns.Goals or {}
local Goals = ns.Goals

-- utils
local function key(factionID) return tonumber(factionID or 0) or 0 end
local function safe(pfn, ...)
    if type(pfn) ~= "function" then return nil end
    local ok, a,b,c,d = pcall(pfn, ...)
    if ok then return a,b,c,d end
end
local function strlower(s) return (type(s)=="string" and s:lower()) or "" end

-- saved goals
function Goals.Get(db, factionID)
    if not db or not db.global then return nil end
    return (db.global.goals or {})[key(factionID)]
end
function Goals.Set(db, factionID, goal)
    if not db or not db.global then return end
    db.global.goals = db.global.goals or {}
    db.global.goals[key(factionID)] = goal
end
function Goals.Clear(db, factionID)
    if not db or not db.global or not db.global.goals then return end
    db.global.goals[key(factionID)] = nil
end

-- tiny fallback (only used for non-renown rows right now)
local FALLBACK_TASKS = {
    { name="World Quest",  rep=150, reset="daily",     zone="Zone",    activityKey="wq_fallback" },
    { name="Dungeon",      rep=75,  reset="repeatable",zone="Any",     activityKey="dungeon_fallback" },
    { name="Weekly Quest", rep=500, reset="weekly",    zone="Capital", activityKey="weekly_fallback" },
}

-- =========================
-- Renown → home-zone map
-- =========================
-- Match by *faction name substring* (lowercased) → list of zone-name substrings to scan.
-- TWW
local HOME_TWW = {
    ["council of dornogal"]          = { "isle of dorn" },
    ["hallowfall arathi"]            = { "hallowfall" },
    ["the assembly of the deeps"]    = { "the ringing deeps" },
    ["the cartels of undermine"]     = { "undermine" },
    ["the severed threads"]          = { "azj-kahet" },
}
-- Dragonflight
local HOME_DF = {
    ["dragonscale expedition"]       = { "the waking shores", "ohn'ahran plains", "the azure span", "thaldraszus" },
    ["iskaara tuskarr"]              = { "the azure span", "ohn'ahran plains", "the waking shores" },
    ["maruuk centaur"]               = { "ohn'ahran plains" },
    ["valdrakken accord"]            = { "thaldraszus" },  -- includes Valdrakken
    ["loamm niffen"]                 = { "zaralek cavern" },
    ["dream wardens"]                = { "emerald dream" },
}
-- Merge (order doesn’t matter)
local RENOWN_HOME = {}
for k,v in pairs(HOME_TWW) do RENOWN_HOME[k]=v end
for k,v in pairs(HOME_DF)  do RENOWN_HOME[k]=v end

-- cache: zone-substring -> {mapIDs}
local _zoneNameToIDs = nil
local function resolveZoneIDsByName(patterns)
    _zoneNameToIDs = _zoneNameToIDs or {}
    if not C_Map or not C_Map.GetMapInfo then return _zoneNameToIDs end
    local need = {}
    for _,pat in ipairs(patterns) do if not _zoneNameToIDs[pat] then need[pat]=true end end
    if next(need) == nil then return _zoneNameToIDs end

    for mapID=1,4000 do
        local info = safe(C_Map.GetMapInfo, mapID)
        local name = info and info.name and info.name:lower()
        if name then
            for pat in pairs(need) do
                if name:find(pat, 1, true) then
                    _zoneNameToIDs[pat] = _zoneNameToIDs[pat] or {}
                    table.insert(_zoneNameToIDs[pat], mapID)
                end
            end
        end
    end
    for pat in pairs(need) do _zoneNameToIDs[pat] = _zoneNameToIDs[pat] or {} end
    return _zoneNameToIDs
end

local function homeZonePatternsFor(row)
    if not row or row.type ~= "renown" then return nil end
    local n = strlower(row.name)
    for pat,zones in pairs(RENOWN_HOME) do
        if n:find(pat, 1, true) then return zones end
    end
    return nil
end

-- build list of mapIDs to scan STRICTLY for the renown’s home zone(s)
local function buildRenownScanMapIDs(row)
    local patterns = homeZonePatternsFor(row)
    if not patterns then return nil end
    local resolved = resolveZoneIDsByName(patterns)
    local set = {}
    for _,pat in ipairs(patterns) do
        local ids = resolved[pat]
        if ids then for _,id in ipairs(ids) do set[id]=true end end
    end
    local out = {}
    for id in pairs(set) do table.insert(out, id) end
    return out
end

local function tagToReset(tag)
    if not tag then return "" end
    if tag.isDaily  then return "daily" end
    if tag.isWeekly then return "weekly" end
    return ""
end

local function makeTask(questID, mapID, renownRow)
    if not questID or questID<=0 then return nil end
    local title = safe(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID) or "World Quest"
    local tag   = safe(C_QuestLog and C_QuestLog.GetQuestTagInfo, questID)
    local reset = tagToReset(tag); if reset=="" then reset="daily" end
    local zone  = ""
    if C_Map and C_Map.GetMapInfo then
        local mi = safe(C_Map.GetMapInfo, mapID); zone = (mi and mi.name) or ""
    end
    return {
        name = title,
        rep  = renownRow and 250 or 150,
        reset = reset,
        zone = zone,
        activityKey = "wq_"..questID,
    }
end

local function collectWQTasksStrict(row)
    -- Only renown rows WITH a known mapping are eligible
    local maps = buildRenownScanMapIDs(row)
    if not maps or #maps==0 or not C_TaskQuest or not C_TaskQuest.GetQuestsForPlayerByMapID then
        return {}
    end

    -- Build a whitelist of zone-name substrings to additionally guard results
    local zoneWhitelists = {}
    local patterns = homeZonePatternsFor(row) or {}
    for _,p in ipairs(patterns) do zoneWhitelists[p]=true end

    local tasks, seen = {}, {}
    for _, mapID in ipairs(maps) do
        -- Prefer the newer API (11.0.5+), fall back to legacy on older builds
        local entries = safe(C_TaskQuest.GetQuestsOnMap, mapID)
        if not entries then
            entries = safe(C_TaskQuest.GetQuestsForPlayerByMapID, mapID)
        end

        if type(entries) == "table" then
            for i = 1, #entries do
                local q   = entries[i]
                local qid = q and (q.questID or q.questId) -- be lenient about field name

                if qid and not seen[qid] then
                    seen[qid] = true

                    -- Only include quests that are currently active for the player.
                    -- Some APIs (like GetQuestsForPlayerByMapID) return every quest
                    -- that could appear on the map, so we need to explicitly check
                    -- for active status/time left.
                    local isActive  = safe(C_TaskQuest.IsActive, qid)
                    local timeLeft  = safe(C_TaskQuest.GetQuestTimeLeftMinutes, qid)
                    local active = (isActive == nil or isActive) and (not timeLeft or timeLeft > 0)

                    if active then
                        local t = makeTask(qid, mapID, true)

                        -- Hard filter: zone name must include one of the home patterns
                        local z = strlower(t.zone)
                        local ok = false
                        for pat in pairs(zoneWhitelists) do
                            if z:find(pat, 1, true) then ok = true; break end
                        end

                        if ok then
                            table.insert(tasks, t)
                        end
                    end
                end
            end
        end
    end


    table.sort(tasks, function(a,b)
        if a.zone == b.zone then return (a.name or "") < (b.name or "") end
        return (a.zone or "") < (b.zone or "")
    end)
    return tasks
end

-- entry
function Goals.GenerateTasks(db, row)
    db.global.completedActivities = db.global.completedActivities or {}
    local fid = key(row and row.factionID)
    db.global.completedActivities[fid] = db.global.completedActivities[fid] or {}
    local completed = db.global.completedActivities[fid]

    local tasks = {}

    if row and row.type == "renown" then
        -- Strict renown logic: only mapped homes produce WQs; otherwise none (avoid wrong zone leakage)
        tasks = collectWQTasksStrict(row)
        -- If nothing found, do NOT substitute random fallbacks for renown (better to show nothing than wrong)
    else
        -- Non-renown: keep the tiny generic fallback for now (until we wire mappings)
        for i=1,#FALLBACK_TASKS do table.insert(tasks, FALLBACK_TASKS[i]) end
    end

    return tasks, completed
end

function Goals.MarkCompleted(db, factionID, activityKey)
    db.global.completedActivities = db.global.completedActivities or {}
    local fid = key(factionID)
    db.global.completedActivities[fid] = db.global.completedActivities[fid] or {}
    db.global.completedActivities[fid][activityKey] = time()
end
