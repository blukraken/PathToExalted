-- goals.lua
-- Goal storage + dynamic task generation (Phase 2 scaffold)
local ADDON_NAME, ns = ...
ns.Goals = ns.Goals or {}
local Goals = ns.Goals

-- shape (saved to db.global.goals[factionID]):
-- { type="faction", targetStandingID=6 }  -- Revered
-- { type="renown",  targetRenown=20 }     -- Renown level

-- Helpers
local function key(factionID) return tonumber(factionID or 0) or 0 end
local function safe(pfn, ...)
    if type(pfn) ~= "function" then return nil end
    local ok, r1, r2, r3, r4 = pcall(pfn, ...)
    if ok then return r1, r2, r3, r4 end
end
local function nz(v, alt) if v == nil then return alt else return v end end

-- Public API: goal store
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

-- ===== Static fallback tasks (kept small on purpose) =====
-- Each task row:
-- { name="World Quest", rep=150, reset="daily", zone="Somewhere", activityKey="wq_123" }
local FALLBACK_TASKS = {
    -- Example: used if we cannot fetch anything live
    { name="World Quest",          rep=150, reset="daily",    zone="Zone",       activityKey="wq_fallback" },
    { name="Dungeon",              rep=75,  reset="repeatable", zone="Any",      activityKey="dungeon_fallback" },
    { name="Weekly Quest",         rep=500, reset="weekly",   zone="Capital",    activityKey="weekly_fallback" },
}

-- ===== Dynamic collectors (Retail 11.x safe) =====

-- Returns an array of mapIDs to scan (player best map + its parents), unique & valid.
local function CollectRelevantMaps()
    if not C_Map or not C_Map.GetBestMapForUnit then return {} end
    local out, seen = {}, {}
    local cur = safe(C_Map.GetBestMapForUnit, "player")
    local function add(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            table.insert(out, id)
        end
    end
    add(cur)

    -- Walk up 2 parent levels (zone -> continent -> world/continent parent)
    local function parentOf(id)
        local info = id and safe(C_Map.GetMapInfo, id)
        return info and info.parentMapID or nil
    end

    local p1 = parentOf(cur); add(p1)
    local p2 = parentOf(p1);  add(p2)

    return out
end

-- Build reset label from tag info
local function TagToReset(tagInfo)
    if not tagInfo then return "" end
    if tagInfo.isDaily then return "daily" end
    if tagInfo.isWeekly then return "weekly" end
    return ""
end

-- Build a dynamic task from a questID + mapID
local function BuildWQTask(questID, mapID, forRenownRow)
    if not questID or questID <= 0 then return nil end
    local title = safe(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID) or "World Quest"
    local tagInfo = safe(C_QuestLog and C_QuestLog.GetQuestTagInfo, questID)
    local reset = TagToReset(tagInfo)
    local mapName = ""
    if C_Map and C_Map.GetMapInfo then
        local mi = safe(C_Map.GetMapInfo, mapID)
        mapName = (mi and mi.name) or ""
    end
    -- Use safe numeric defaults; renown rows generally value higher
    local repGuess = forRenownRow and 250 or 150
    return {
        name = title,
        rep = repGuess,
        reset = (reset ~= "" and reset) or "daily",
        zone = mapName,
        activityKey = "wq_" .. tostring(questID),
    }
end

-- Collect available world quests around the player (current zone + parents).
local function CollectWorldQuestTasks(row)
    local tasks = {}
    if not C_TaskQuest or not C_TaskQuest.GetQuestsForPlayerByMapID then
        return tasks
    end

    local dedup = {}
    local maps = CollectRelevantMaps()
    for _, mapID in ipairs(maps) do
        local entries = safe(C_TaskQuest.GetQuestsForPlayerByMapID, mapID)
        if entries then
            for i=1, #entries do
                local e = entries[i]
                local qid = e and e.questID
                if qid and not dedup[qid] then
                    dedup[qid] = true
                    local t = BuildWQTask(qid, mapID, row and row.type == "renown")
                    if t then table.insert(tasks, t) end
                end
            end
        end
    end

    -- Sort by zone then name for stability
    table.sort(tasks, function(a,b)
        if a.zone == b.zone then return (a.name or "") < (b.name or "") end
        return (a.zone or "") < (b.zone or "")
    end)

    return tasks
end

-- ===== Task generation entry point =====
-- Returns: tasks (array), completed (set of keys) for the current character or warband (future)
function Goals.GenerateTasks(db, row)
    db.global.completedActivities = db.global.completedActivities or {} -- map[factionID][activityKey] = lastCompletedEpoch
    local fid = key(row and row.factionID)
    local completedRoot = db.global.completedActivities
    completedRoot[fid] = completedRoot[fid] or {}
    local completed = completedRoot[fid]

    -- 1) Dynamic: world quests visible to the player in current map context
    local worldQuestTasks = CollectWorldQuestTasks(row)

    -- 2) If nothing dynamic found, fallback to a minimal static list
    local tasks = {}
    if #worldQuestTasks > 0 then
        tasks = worldQuestTasks
    else
        -- Keep the placeholder list tiny to avoid noise
        for i=1, #FALLBACK_TASKS do
            local ft = FALLBACK_TASKS[i]
            -- Bump rep a touch for renown rows to feel directionally right
            local repAdj = (row and row.type == "renown") and 100 or 0
            table.insert(tasks, {
                name = ft.name, rep = nz(ft.rep, 0) + repAdj, reset = ft.reset, zone = ft.zone, activityKey = ft.activityKey
            })
        end
    end

    return tasks, completed
end

-- Mark a task completed (scaffold). Real logic will incorporate reset windows.
function Goals.MarkCompleted(db, factionID, activityKey)
    db.global.completedActivities = db.global.completedActivities or {}
    local fid = key(factionID)
    db.global.completedActivities[fid] = db.global.completedActivities[fid] or {}
    db.global.completedActivities[fid][activityKey] = time()
end
