-- goals.lua
-- Goal storage + basic task generation (stub data)
local ADDON_NAME, ns = ...
ns.Goals = ns.Goals or {}
local Goals = ns.Goals

-- shape (saved to db.global.goals[factionID]):
-- { type="faction", targetStandingID=6 }  -- Revered
-- { type="renown",  targetRenown=20 }     -- Renown level

-- Helpers
local function key(factionID) return tonumber(factionID or 0) or 0 end

-- Public API
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

-- ===== Task Scaffolding =====
-- This is intentionally tiny placeholder data so the UI can render.
-- Replace/expand with real activities in a later pass.
-- Each task row:
-- { name="World Quest: Supply Run", rep=150, reset="daily", zone="Somewhere", activityKey="wq_123" }
local TASKS = {
    -- Example IDs — fill with real factionID/majorFactionID later.
    [2503] = { -- Dragonscale Expedition (example)
        { name="World Quest",          rep=150, reset="daily",  zone="Dragon Isles", activityKey="wq_generic" },
        { name="Contracts (Emissary)", rep=10,  reset="per_kill", zone="Various",   activityKey="contract_kill" },
        { name="Weekly Quest",         rep=500, reset="weekly", zone="Valdrakken",  activityKey="weekly_generic" },
    },
    -- Renown (major factions) can reuse same table keyed by factionID
}

-- Returns: tasks (array), completed (set of keys) for the current character or warband (future)
function Goals.GenerateTasks(db, row)
    local fid = key(row.factionID)
    local tasks = TASKS[fid] or {
        { name="World Quest", rep=(row.type=="renown" and 250 or 150), reset="daily",  zone="Zone", activityKey="wq_fallback" },
        { name="Dungeon",     rep=75,  reset="repeatable", zone="Any",  activityKey="dungeon_fallback" },
        { name="Weekly",      rep=500, reset="weekly",      zone="City", activityKey="weekly_fallback" },
    }

    -- Placeholder completion store (future Phase 5 upgrades: warband-aware, per reset)
    db.global.completedActivities = db.global.completedActivities or {} -- map[factionID][activityKey] = lastCompletedEpoch
    local croot = db.global.completedActivities
    croot[fid] = croot[fid] or {}
    local completed = croot[fid]

    return tasks, completed
end

-- Mark a task completed (scaffold). Real logic will incorporate reset windows.
function Goals.MarkCompleted(db, factionID, activityKey)
    db.global.completedActivities = db.global.completedActivities or {}
    local fid = key(factionID)
    db.global.completedActivities[fid] = db.global.completedActivities[fid] or {}
    db.global.completedActivities[fid][activityKey] = time()
end
