-- Create a local addon object to store our functions and variables.
-- This is the best practice to avoid conflicts with other addons.
local addonName, addon = ...
PathToExalted = addon -- Make our addon table globally accessible for the XML

-- A table to hold our reputation data
addon.Reputations = {}

--------------------------------------------------------------------------------
-- Core Functions
--------------------------------------------------------------------------------

-- Scans all reputations and stores them in the addon.Reputations table.
function addon:ScanReputations()
    wipe(addon.Reputations) -- Clear old data
    local numFactions = C_Reputation.GetNumFactions()

    for i = 1, numFactions do
        local factionInfo = C_Reputation.GetFactionInfoByIndex(i)

        -- We only track factions that have a progress bar and are not headers.
        if factionInfo and factionInfo.hasRep and not factionInfo.isHeader then
            local name = factionInfo.name
            local currentRep = C_Reputation.GetFactionReputation(factionInfo.factionID)
            -- The 'select' function here is a safe way to get paragon reputation if it exists.
            local maxRep = select(4, C_Reputation.GetReputationParagonInfo(factionInfo.factionID)) or factionInfo.repMax

            table.insert(addon.Reputations, {
                name = name,
                id = factionInfo.factionID,
                value = currentRep,
                max = maxRep,
            })
        end
    end
    print(addonName .. ": Scan complete. Found " .. #addon.Reputations .. " reputations to track.")
end

--------------------------------------------------------------------------------
-- UI Functions
--------------------------------------------------------------------------------

-- Toggles the visibility of the main addon window.
function addon:Toggle()
    -- PathToExaltedFrame is the name we gave our main frame in the XML file.
    if PathToExaltedFrame:IsShown() then
        PathToExaltedFrame:Hide()
    else
        PathToExaltedFrame:Show()
    end
end

-- This function will be called when the addon's main frame is shown.
function addon:OnShow()
    print(addonName .. ": Frame shown.")
    -- We scan the reputations every time the window is opened to ensure data is fresh.
    addon:ScanReputations()
    -- (We will add code here later to display the data)
end

-- This function will be called when the addon's main frame is hidden.
function addon:OnHide()
    print(addonName .. ": Frame hidden.")
    -- (We can add code here later to save data if needed)
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

-- Create a slash command to open the addon.
SLASH_PATHTOEXALTED1 = "/pte"
function SlashCmdList.PATHTOEXALTED(msg, editbox)
    -- This is the function that runs when you type /pte
    addon:Toggle()
end

-- Create a small, invisible frame to handle game events.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    -- We only want to run our setup code once our addon has loaded.
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize our saved variables database.
        -- This table will persist between game sessions.
        PathToExaltedDB = PathToExaltedDB or {}

        print(addonName .. " has been loaded. Type /pte to open.")

        -- We don't need to listen for this event anymore.
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
