-- UIEssentials
local addonName, addon = ...

-- ========================================
-- CONSTANTS
-- ========================================
local CONSTANTS = {
    CACHE_TIMEOUT = 0.75,
    CACHE_CLEANUP_INTERVAL = 5,
    MAX_PARTY_MEMBERS = 4,
    MAX_RAID_MEMBERS = 40,
    MAX_NAMEPLATES = 40,
    
    COLORS = {
        LABEL = "|cffff6600",
        ME = "|cff00ff00",
        FRIENDLY = "|cff00ff00",
        NEUTRAL = "|cffffff00",
        HOSTILE = "|cffff0000",
        DEFAULT = "|cffffffff"
    },
    
    ILVL_COLORS = {
        GREY = "|cff9d9d9d",
        GREEN = "|cff1eff00",
        BLUE = "|cff0070dd",
        PURPLE = "|cffa335ee",
        ORANGE = "|cffff8000"
    },
    
    REALM_FRAME_PATTERNS = {
        "^PartyMemberFrame%d",
        "^CompactRaidFrame%d",
        "^CompactRaidGroup%dMember%d",
        "^CompactPartyFrameMember%d"
    }
}

local DEFAULTS = {
    enableTooltips = true,
    hideRealmRaid = true,
    hideRealmParty = true,
    showItemLevelDecimals = true,
    showCursorHighlight = false,
    cursorStyle = "square", -- "square" or "starsurge"
    autoSkipCutscenes = true,
    disableAutoCompare = true,
}

-- ========================================
-- SETTINGS MODULE
-- ========================================
local SettingsManager = {}

function SettingsManager:Initialize()
    UIEssentials = UIEssentials or {}
    
    -- Merge defaults with saved settings
    for key, value in pairs(DEFAULTS) do
        if UIEssentials[key] == nil then
            UIEssentials[key] = value
        end
    end
    
    return UIEssentials
end

function SettingsManager:Get(key)
    return UIEssentials and UIEssentials[key]
end

function SettingsManager:Set(key, value)
    if UIEssentials then
        UIEssentials[key] = value
    end
end

-- ========================================
-- CACHE MODULE
-- ========================================
local Cache = {}
Cache.data = {}

function Cache:Get(guid)
    -- Handle tainted GUIDs in secure contexts
    local success, result = pcall(function()
        local cached = self.data[guid]
        if not cached then return nil end
        
        if GetTime() - cached.timestamp > CONSTANTS.CACHE_TIMEOUT then
            self.data[guid] = nil
            return nil
        end
        
        return cached.data
    end)
    
    if success then
        return result
    else
        return nil
    end
end

function Cache:Set(guid, data)
    -- Handle tainted GUIDs in secure contexts
    pcall(function()
        self.data[guid] = {
            data = data,
            timestamp = GetTime()
        }
    end)
end

function Cache:Clean()
    local currentTime = GetTime()
    for guid, cached in pairs(self.data) do
        if currentTime - cached.timestamp > CONSTANTS.CACHE_TIMEOUT then
            self.data[guid] = nil
        end
    end
end

function Cache:StartCleanupTimer()
    -- Use C_Timer instead of OnUpdate for better performance
    C_Timer.NewTicker(CONSTANTS.CACHE_CLEANUP_INTERVAL, function()
        -- Don't clean cache during combat for better performance
        if not InCombatLockdown() then
            Cache:Clean()
        end
    end)
end

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================
local Utils = {}

function Utils.StripRealm(name)
    if not name then return "" end
    
    -- Safely handle potentially tainted names
    local success, result = pcall(function()
        return name:match("^([^-]+)") or name
    end)
    
    if success and result then
        return result
    else
        -- If tainted or error, return empty string
        return ""
    end
end

function Utils.GetUnitColor(unit)
    -- Safely handle potentially tainted unit data
    local success, result = pcall(function()
        if UnitIsPlayer(unit) then
            local _, class = UnitClass(unit)
            if class then
                local classColor = RAID_CLASS_COLORS[class]
                if classColor then
                    return string.format("|cff%02x%02x%02x", 
                        classColor.r * 255, 
                        classColor.g * 255, 
                        classColor.b * 255)
                end
            end
        else
            local reaction = UnitReaction(unit, "player")
            if reaction then
                if reaction >= 5 then return CONSTANTS.COLORS.FRIENDLY
                elseif reaction == 4 then return CONSTANTS.COLORS.NEUTRAL
                else return CONSTANTS.COLORS.HOSTILE
                end
            end
        end
        
        return CONSTANTS.COLORS.DEFAULT
    end)
    
    if success and result then
        return result
    else
        return CONSTANTS.COLORS.DEFAULT
    end
end

function Utils.FindUnitByGUID(guid)
    if not guid then return nil end
    
    -- Helper function to safely compare GUIDs (handles tainted values)
    local function compareGUID(unitToken)
        if not UnitExists(unitToken) then return false end
        local success, isMatch = pcall(function()
            return UnitGUID(unitToken) == guid
        end)
        return success and isMatch
    end
    
    -- Check common units first (most likely)
    local commonUnits = {"mouseover", "target", "focus"}
    for _, unitToken in ipairs(commonUnits) do
        if compareGUID(unitToken) then
            return unitToken
        end
    end
    
    -- Check party members (limit to actual party size)
    if IsInGroup() and not IsInRaid() then
        local numPartyMembers = GetNumGroupMembers()
        local maxParty = math.min(numPartyMembers > 0 and numPartyMembers or CONSTANTS.MAX_PARTY_MEMBERS, CONSTANTS.MAX_PARTY_MEMBERS)
        for i = 1, maxParty do
            local partyUnit = "party" .. i
            if compareGUID(partyUnit) then
                return partyUnit
            end
        end
    end
    
    -- Check raid members (limit to actual raid size)
    if IsInRaid() then
        local numRaidMembers = GetNumGroupMembers()
        local maxRaid = math.min(numRaidMembers > 0 and numRaidMembers or CONSTANTS.MAX_RAID_MEMBERS, CONSTANTS.MAX_RAID_MEMBERS)
        for i = 1, maxRaid do
            local raidUnit = "raid" .. i
            if compareGUID(raidUnit) then
                return raidUnit
            end
        end
    end
    
    -- Check nameplates (only scan visible ones)
    local numNameplates = C_NamePlate and C_NamePlate.GetNumNamePlates() or 0
    if numNameplates > 0 then
        local maxNameplates = math.min(numNameplates, CONSTANTS.MAX_NAMEPLATES)
        for i = 1, maxNameplates do
            local nameplateUnit = "nameplate" .. i
            if compareGUID(nameplateUnit) then
                return nameplateUnit
            end
        end
    end
    
    return nil
end

function Utils.MatchesFramePattern(frameName)
    if not frameName then return false end
    
    for _, pattern in ipairs(CONSTANTS.REALM_FRAME_PATTERNS) do
        if frameName:match(pattern) then
            return true
        end
    end
    
    return false
end

function Utils.GetILvlColor(ilvl)
    if not ilvl then return CONSTANTS.ILVL_COLORS.GREY end
    if ilvl >= 265 then return CONSTANTS.ILVL_COLORS.ORANGE end
    if ilvl >= 250  then return CONSTANTS.ILVL_COLORS.PURPLE end
    if ilvl >= 235 then return CONSTANTS.ILVL_COLORS.BLUE end
    if ilvl >= 220 then return CONSTANTS.ILVL_COLORS.GREEN end
    return CONSTANTS.ILVL_COLORS.GREY
end

function Utils.GetUnitItemLevel(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    
    -- For the player, use the reliable API
    if UnitIsUnit(unit, "player") then
        local _, avgItemLevelEquipped = GetAverageItemLevel()
        return avgItemLevelEquipped and math.floor(avgItemLevelEquipped) or nil
    end
    
    -- For other players, try the inspect API first (Retail WoW)
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
        if ilvl and ilvl > 0 then
            return math.floor(ilvl)
        end
    end
    
    -- Fallback: manual calculation (less reliable, but works in some cases)
    -- Only use slots that are commonly equipped to avoid weird values
    local total, count = 0, 0
    local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17} -- Exclude shirt(4) and tabard(19)
    
    for _, slotId in ipairs(slots) do
        local itemLink = GetInventoryItemLink(unit, slotId)
        if itemLink then
            local itemLevel = GetDetailedItemLevelInfo(itemLink)
            if itemLevel and itemLevel > 0 and itemLevel < 1000 then -- Sanity check
                total = total + itemLevel
                count = count + 1
            end
        end
    end
    
    -- Only return if we have a reasonable number of items (at least 8)
    if count >= 8 then
        return math.floor(total / count)
    end
    
    return nil
end

-- ========================================
-- ITEM LEVEL INSPECTOR MODULE
-- ========================================
local ItemLevelInspector = {}
ItemLevelInspector.cache = {}

function ItemLevelInspector:GetItemLevel(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    if UnitIsUnit(unit, "player") then return Utils.GetUnitItemLevel(unit) end
    
    local guid = UnitGUID(unit)
    if not guid then return nil end
    
    -- Check cache (5 min)
    local cached = self.cache[guid]
    if cached and (GetTime() - cached.time) < 300 then
        return cached.ilvl
    end
    
    -- Try to read inspection data if it's already loaded (don't request)
    local ilvl = Utils.GetUnitItemLevel(unit)
    
    -- If we don't have ilvl and can inspect, request inspection
    if not ilvl or ilvl == 0 then
        local canInspect = CanInspect(unit)
        local inRange = CheckInteractDistance(unit, 1)
        if canInspect and inRange then
            -- Request inspection - it will be cached when INSPECT_READY fires
            NotifyInspect(unit)
        end
    end
    
    -- Sanity check: item level should be reasonable (between 1 and 300 for current retail)
    if ilvl and ilvl > 0 and ilvl < 300 then
        self.cache[guid] = {ilvl = ilvl, time = GetTime()}
        return ilvl
    end
    
    return nil
end

function ItemLevelInspector:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("INSPECT_READY")
    frame:SetScript("OnEvent", function(self, event, guid)
        -- Passively cache item level data when inspections happen
        local unit = Utils.FindUnitByGUID(guid)
        if unit then
            local ilvl = Utils.GetUnitItemLevel(unit)
            -- Sanity check: item level should be reasonable (between 1 and 300 for current retail)
            if ilvl and ilvl > 0 and ilvl < 300 then
                ItemLevelInspector.cache[guid] = {ilvl = ilvl, time = GetTime()}
            end
        end
    end)
end

-- ========================================
-- TARGETING SCANNER MODULE
-- ========================================
local TargetingScanner = {}

function TargetingScanner.IsUnitTargeting(scanUnit, targetUnit)
    if not UnitExists(scanUnit) then return false end
    
    local scanTarget = scanUnit .. "target"
    if not UnitExists(scanTarget) then return false end
    
    -- Safely check if units match (handles tainted values in secure contexts)
    -- The boolean test must happen INSIDE pcall to catch taint errors
    local success, isMatch = pcall(function()
        -- Perform the boolean test inside pcall where taint errors can be caught
        local match = UnitIsUnit(scanTarget, targetUnit)
        -- Force the test to happen by using it in a conditional
        if match then
            return "yes"
        else
            return "no"
        end
    end)
    
    -- If pcall succeeded and returned "yes", units match
    -- Otherwise (pcall failed due to taint, or returned "no"), no match
    return success and isMatch == "yes"
end

function TargetingScanner.AddTargeter(scanUnit, targeters, checkDuplicates)
    local name = UnitName(scanUnit)
    if not name then return end
    
    name = Utils.StripRealm(name)
    
    -- Check for duplicates if requested
    if checkDuplicates then
        for _, targeter in ipairs(targeters) do
            if targeter.name == name then return end
        end
    end
    
    table.insert(targeters, {unit = scanUnit, name = name})
end

function TargetingScanner.ScanUnits(prefix, count, targetUnit, targeters, checkDuplicates)
    for i = 1, count do
        local scanUnit = prefix .. i
        if TargetingScanner.IsUnitTargeting(scanUnit, targetUnit) then
            TargetingScanner.AddTargeter(scanUnit, targeters, checkDuplicates)
        end
    end
end

function TargetingScanner.GetUnitsTargeting(targetUnit)
    -- Early return if target unit doesn't exist
    if not targetUnit or not UnitExists(targetUnit) then
        return {}
    end
    
    local targeters = {}
    
    -- Check player first
    if TargetingScanner.IsUnitTargeting("player", targetUnit) then
        TargetingScanner.AddTargeter("player", targeters, false)
    end
    
    -- Enable duplicate checking for all subsequent scans to prevent duplicates
    -- (e.g., when targeting yourself, both player and nameplate might match)
    local checkDuplicates = true
    
    -- Check party (only if not in raid to avoid duplicates)
    if IsInGroup() and not IsInRaid() then
        TargetingScanner.ScanUnits("party", CONSTANTS.MAX_PARTY_MEMBERS, targetUnit, targeters, checkDuplicates)
    end
    
    -- Check raid (limit to actual raid size for better performance)
    if IsInRaid() then
        local numRaidMembers = GetNumGroupMembers()
        local maxToScan = math.min(numRaidMembers > 0 and numRaidMembers or CONSTANTS.MAX_RAID_MEMBERS, CONSTANTS.MAX_RAID_MEMBERS)
        TargetingScanner.ScanUnits("raid", maxToScan, targetUnit, targeters, checkDuplicates)
    end
    
    -- Check nameplates (skip in raids for performance, and limit scan)
    if not IsInRaid() then
        -- Only scan visible nameplates (typically much less than 40)
        local numNameplates = C_NamePlate and C_NamePlate.GetNumNamePlates() or 0
        if numNameplates > 0 then
            local maxNameplates = math.min(numNameplates, CONSTANTS.MAX_NAMEPLATES)
            TargetingScanner.ScanUnits("nameplate", maxNameplates, targetUnit, targeters, checkDuplicates)
        end
    end
    
    return targeters
end

-- ========================================
-- TOOLTIP RENDERER MODULE
-- ========================================
local TooltipRenderer = {}

function TooltipRenderer.RenderTargetLine(targetUnit)
    -- Safely check if target is player (handles tainted values in secure contexts)
    local success, result = pcall(function()
        if UnitIsUnit(targetUnit, "player") then
            return CONSTANTS.COLORS.LABEL .. "Target: |r" .. CONSTANTS.COLORS.ME .. "Me|r"
        end
        return nil
    end)
    
    -- If the check succeeded and returned a value, use it
    if success and result then
        return result
    end
    
    -- Otherwise, show the target's name
    local targetName = UnitName(targetUnit)
    if not targetName then return "" end
    
    targetName = Utils.StripRealm(targetName)
    local color = Utils.GetUnitColor(targetUnit)
    
    return CONSTANTS.COLORS.LABEL .. "Target: |r" .. color .. targetName .. "|r"
end

function TooltipRenderer.RenderTargetersList(targeters)
    local lines = {}
    
    -- Header
    if #targeters == 1 then
        table.insert(lines, CONSTANTS.COLORS.LABEL .. "Targeted by:|r")
    else
        table.insert(lines, CONSTANTS.COLORS.LABEL .. "Targeted by " .. #targeters .. " units:|r")
    end
    
    -- Targeters
    for _, targeter in ipairs(targeters) do
        local color = Utils.GetUnitColor(targeter.unit)
        table.insert(lines, "  " .. color .. targeter.name .. "|r")
    end
    
    return lines
end

function TooltipRenderer.RenderItemLevel(ilvl)
    if not ilvl then return "" end
    
    local color = Utils.GetILvlColor(ilvl)
    return CONSTANTS.COLORS.LABEL .. "iLvl: |r" .. color .. ilvl .. "|r"
end

function TooltipRenderer.ApplyTooltip(tooltip, ilvlText, targetText, targeterLines)
    -- Safely add lines with individual pcall protection
    -- Note: TooltipDataProcessor callbacks should be safe to modify tooltips
    if ilvlText and ilvlText ~= "" then
        pcall(function() tooltip:AddLine(ilvlText) end)
    end
    
    if targetText and targetText ~= "" then
        pcall(function() tooltip:AddLine(targetText) end)
    end
    
    if targeterLines and #targeterLines > 0 then
        pcall(function() tooltip:AddLine(" ") end)
        for _, line in ipairs(targeterLines) do
            pcall(function() tooltip:AddLine(line) end)
        end
    end
    
    -- Don't call Show() - let the game handle tooltip visibility
end

-- ========================================
-- TOOLTIP HANDLER MODULE
-- ========================================
local TooltipHandler = {}

function TooltipHandler.AddTargetInfo(tooltip, data)
    if not data or not data.guid then return end
    if not SettingsManager:Get("enableTooltips") then return end
    
    -- Wrap everything in pcall to prevent taint from spreading
    local success = pcall(function()
        -- Try cache first
        local cached = Cache:Get(data.guid)
        if cached then
            TooltipRenderer.ApplyTooltip(tooltip, cached.ilvlText, cached.targetText, cached.targeterLines)
            return
        end
        
        -- Find unit
        local unit = Utils.FindUnitByGUID(data.guid)
        if not unit or not UnitExists(unit) then return end
        
        -- Build tooltip data
        local ilvlText = ""
        local targetText = ""
        local targeterLines = {}
        
        -- Get item level (only for players)
        if UnitIsPlayer(unit) then
            local ilvl = ItemLevelInspector:GetItemLevel(unit)
            if ilvl then
                ilvlText = TooltipRenderer.RenderItemLevel(ilvl)
            end
        end
        
        -- Who is this unit targeting? (only check if unit exists to avoid unnecessary work)
        -- Try to get target info, but handle cases where it might be blocked
        local targetUnit = unit .. "target"
        local targetSuccess, targetExists = pcall(function() return UnitExists(targetUnit) end)
        if targetSuccess and targetExists then
            local renderSuccess, renderResult = pcall(function() return TooltipRenderer.RenderTargetLine(targetUnit) end)
            if renderSuccess and renderResult then
                targetText = renderResult
            end
        end
        
        -- Who is targeting this unit? (only scan if we're not in a large raid for performance)
        -- Skip targeting scan in large raids (20+ members) as it's expensive and less useful
        local numRaidMembers = IsInRaid() and GetNumGroupMembers() or 0
        if numRaidMembers < 20 then
            local scanSuccess, targeters = pcall(function() return TargetingScanner.GetUnitsTargeting(unit) end)
            if scanSuccess and targeters and #targeters > 0 then
                targeterLines = TooltipRenderer.RenderTargetersList(targeters)
            end
        end
        
        -- Cache the results (including empty results to avoid repeated lookups)
        Cache:Set(data.guid, {
            ilvlText = ilvlText,
            targetText = targetText,
            targeterLines = targeterLines
        })
        
        TooltipRenderer.ApplyTooltip(tooltip, ilvlText, targetText, targeterLines)
    end)
    
    -- If pcall failed, silently ignore to prevent taint issues
    if not success then return end
end

function TooltipHandler.Initialize()
    -- Use both TooltipDataProcessor and GameTooltip hook for better compatibility
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        -- Only process if it's the GameTooltip and we have valid unit data
        if tooltip == GameTooltip and data and data.guid then
            -- Additional safety: only proceed if data looks like a unit (not an item)
            if data.type == Enum.TooltipDataType.Unit then
                -- Wrap in pcall to handle any taint issues gracefully
                pcall(TooltipHandler.AddTargetInfo, tooltip, data)
            end
        end
    end)
    
    -- Also hook GameTooltip:SetUnit as a fallback for when TooltipDataProcessor doesn't fire
    hooksecurefunc(GameTooltip, "SetUnit", function(self, unit)
        if not unit or not UnitExists(unit) then return end
        if not SettingsManager:Get("enableTooltips") then return end
        
        -- Get GUID from unit
        local guid = UnitGUID(unit)
        if not guid then return end
        
        -- Use a small delay to ensure tooltip is fully populated
        C_Timer.After(0.01, function()
            if GameTooltip:IsShown() and UnitGUID(unit) == guid then
                pcall(function()
                    TooltipHandler.AddTargetInfo(GameTooltip, {guid = guid, type = Enum.TooltipDataType.Unit})
                end)
            end
        end)
    end)
end

-- ========================================
-- REALM NAME REMOVAL MODULE
-- ========================================
local RealmNameRemoval = {}

function RealmNameRemoval.StripRealmFromFrame(frame)
    if not frame or frame:IsForbidden() then return end
    if not frame.unit or not frame.name then return end
    if not UnitIsPlayer(frame.unit) then return end
    
    local unitName = GetUnitName(frame.unit, true)
    if unitName then
        frame.name:SetText(unitName:match("[^-]+"))
    end
end

function RealmNameRemoval.InitializeRaidFrames()
    if not SettingsManager:Get("hideRealmRaid") then return end
    
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if frame and not frame:IsForbidden() and frame.GetName then
            local frameName = frame:GetName()
            if Utils.MatchesFramePattern(frameName) then
                RealmNameRemoval.StripRealmFromFrame(frame)
            end
        end
    end)
end

function RealmNameRemoval.InitializePartyFrames()
    if not SettingsManager:Get("hideRealmParty") then return end
    
    if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        hooksecurefunc("UnitFrame_Update", function()
            for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                local unitName = GetUnitName(frame.unit, true)
                if unitName then
                    frame.name:SetText(unitName:match("[^-]+"))
                end
            end
        end)
    elseif WOW_PROJECT_ID == WOW_PROJECT_CLASSIC or WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC then
        hooksecurefunc("UnitFrame_Update", function(frame)
            if frame and not frame:IsForbidden() and frame:GetName() then
                if frame:GetName():match("^PartyMemberFrame%d") and frame.unit and frame.name then
                    local unitName = GetUnitName(frame.unit, true)
                    if unitName then
                        frame.name:SetText(unitName:match("[^-]+"))
                    end
                end
            end
        end)
    end
end

function RealmNameRemoval.Initialize()
    RealmNameRemoval.InitializeRaidFrames()
    RealmNameRemoval.InitializePartyFrames()
end

-- ========================================
-- ITEM LEVEL DECIMAL MODULE
-- ========================================
local ItemLevelDecimal = {}
ItemLevelDecimal.isHooked = false
ItemLevelDecimal.isUpdating = false

function ItemLevelDecimal.UpdateDisplay()
    -- Force update the item level display
    if CharacterStatsPane and CharacterStatsPane.ItemLevelFrame and CharacterStatsPane.ItemLevelFrame.Value then
        local itemLevelText = CharacterStatsPane.ItemLevelFrame.Value
        local _, avgItemLevelEquipped = GetAverageItemLevel()
        
        if avgItemLevelEquipped and avgItemLevelEquipped > 0 then
            ItemLevelDecimal.isUpdating = true
            if SettingsManager:Get("showItemLevelDecimals") then
                itemLevelText:SetText(string.format("%.2f", avgItemLevelEquipped))
            else
                itemLevelText:SetText(math.floor(avgItemLevelEquipped))
            end
            ItemLevelDecimal.isUpdating = false
        end
    end
end

function ItemLevelDecimal.SetupHook()
    -- Only hook once
    if ItemLevelDecimal.isHooked then return true end
    
    -- Wait for CharacterStatsPane to exist
    if not CharacterStatsPane or not CharacterStatsPane.ItemLevelFrame or not CharacterStatsPane.ItemLevelFrame.Value then
        return false
    end
    
    local itemLevelText = CharacterStatsPane.ItemLevelFrame.Value
    
    -- Hook SetText to automatically add decimals to item level display
    hooksecurefunc(itemLevelText, "SetText", function(self, text)
        -- Check if feature is enabled
        if not SettingsManager:Get("showItemLevelDecimals") then return end
        
        -- Prevent infinite recursion
        if ItemLevelDecimal.isUpdating then return end
        
        -- Only modify if it's a whole number without decimals
        if text and tonumber(text) and not string.find(text, "%.") then
            local _, avgItemLevelEquipped = GetAverageItemLevel()
            
            if avgItemLevelEquipped and avgItemLevelEquipped > 0 then
                local roundedValue = math.floor(avgItemLevelEquipped)
                
                -- Only replace if text matches the rounded item level
                if tonumber(text) == roundedValue then
                    ItemLevelDecimal.isUpdating = true
                    self:SetText(string.format("%.2f", avgItemLevelEquipped))
                    ItemLevelDecimal.isUpdating = false
                end
            end
        end
    end)
    
    ItemLevelDecimal.isHooked = true
    return true
end

function ItemLevelDecimal.TrySetupHook()
    if not ItemLevelDecimal.SetupHook() then
        -- Retry if frame not ready yet
        C_Timer.After(0.5, ItemLevelDecimal.TrySetupHook)
    else
        -- Hook is ready, update display immediately if character frame is shown
        if CharacterFrame and CharacterFrame:IsShown() then
            ItemLevelDecimal.UpdateDisplay()
        end
    end
end

function ItemLevelDecimal.Initialize()
    -- Only initialize if feature is enabled
    if not SettingsManager:Get("showItemLevelDecimals") then return end
    
    -- Setup hook when character frame is shown
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", function()
            ItemLevelDecimal.TrySetupHook()
            -- Update display when character frame is shown
            C_Timer.After(0.1, ItemLevelDecimal.UpdateDisplay)
        end)
        
        -- Setup immediately if character frame is already open
        if CharacterFrame:IsShown() then
            ItemLevelDecimal.TrySetupHook()
        end
    end
end

-- ========================================
-- CUTSCENE SKIPPER MODULE
-- ========================================
local CutsceneSkipper = {}
CutsceneSkipper.monitorFrame = nil
CutsceneSkipper.isInitialized = false
CutsceneSkipper.skipTimer = nil

function CutsceneSkipper.SkipCutscene()
    -- Cancel any pending skip timer to avoid multiple attempts
    if CutsceneSkipper.skipTimer then
        CutsceneSkipper.skipTimer:Cancel()
        CutsceneSkipper.skipTimer = nil
    end
    
    CutsceneSkipper.skipTimer = C_Timer.NewTimer(0.1, function()
        if C_Movie and C_Movie.IsPlayingMovie and C_Movie.IsPlayingMovie() then
            if C_Movie.StopMovie then 
                C_Movie.StopMovie() 
            end
        end
        
        if CinematicFrame and CinematicFrame:IsShown() then
            if CinematicFrame_CancelCinematic then 
                CinematicFrame_CancelCinematic() 
            else
                CinematicFrame:Hide()
            end
        end
        
        if MovieFrame and MovieFrame:IsShown() then
            if MovieFrame.CloseDialog then
                MovieFrame.CloseDialog:Click()
            elseif GameMovieFinished then
                GameMovieFinished()
            else
                MovieFrame:Hide()
            end
        end
        
        CutsceneSkipper.skipTimer = nil
    end)
end

function CutsceneSkipper.Enable()
    if CutsceneSkipper.isInitialized then return end
    
    if not CutsceneSkipper.monitorFrame then 
        CutsceneSkipper.monitorFrame = CreateFrame("Frame") 
    end
    
    local f = CutsceneSkipper.monitorFrame
    f:RegisterEvent("PLAY_MOVIE")
    f:RegisterEvent("CINEMATIC_START")
    
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAY_MOVIE" or event == "CINEMATIC_START" then
            CutsceneSkipper.SkipCutscene()
        end
    end)
    
    if MovieFrame and not CutsceneSkipper.movieFrameHooked then
        MovieFrame:HookScript("OnShow", function()
            CutsceneSkipper.SkipCutscene()
        end)
        CutsceneSkipper.movieFrameHooked = true
    end

    if CinematicFrame and not CutsceneSkipper.cinematicFrameHooked then
        CinematicFrame:HookScript("OnShow", function()
            CutsceneSkipper.SkipCutscene()
        end)
        CutsceneSkipper.cinematicFrameHooked = true
    end
    
    CutsceneSkipper.isInitialized = true
end

function CutsceneSkipper.Disable()
    if not CutsceneSkipper.isInitialized then return end
    
    if CutsceneSkipper.skipTimer then
        CutsceneSkipper.skipTimer:Cancel()
        CutsceneSkipper.skipTimer = nil
    end
    
    if CutsceneSkipper.monitorFrame then
        CutsceneSkipper.monitorFrame:UnregisterAllEvents()
        CutsceneSkipper.monitorFrame:SetScript("OnEvent", nil)
    end
    
    CutsceneSkipper.isInitialized = false
end

function CutsceneSkipper.Initialize()
    if SettingsManager:Get("autoSkipCutscenes") then 
        CutsceneSkipper.Enable() 
    else 
        CutsceneSkipper.Disable() 
    end
end

-- ========================================
-- AUTO-COMPARE DISABLER MODULE
-- ========================================
local AutoCompareDisabler = {}

function AutoCompareDisabler.ApplySetting()

    local shouldDisable = SettingsManager:Get("disableAutoCompare")
    if shouldDisable then
        SetCVar("alwaysCompareItems", "0")
    else
        SetCVar("alwaysCompareItems", "1")
    end
end

function AutoCompareDisabler.Initialize()
    AutoCompareDisabler.ApplySetting()
    

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(self, event)
        AutoCompareDisabler.ApplySetting()
    end)
end

-- ========================================
-- CURSOR HIGHLIGHT MODULE
-- ========================================
local CursorHighlight = {}
CursorHighlight.frame = nil
CursorHighlight.modelFrame = nil
CursorHighlight.scaleTicker = nil

-- Constants
local CURSOR_SIZE = 13.25
local CURSOR_COLOR = {0, 1, 0, 1.0}
local SCALE_UPDATE_INTERVAL = 1.0

-- Star Surge constants
local STAR_SURGE_MODEL_ID = 1513212
local STAR_SURGE_SCALE = 0.001
local STAR_SURGE_ALPHA = 1.0
local STAR_SURGE_OFFSET_X = 8
local STAR_SURGE_OFFSET_Y = -8
local STAR_SURGE_MOVEMENT_THRESHOLD = 0.1

function CursorHighlight.CreateHighlightFrame()
    if CursorHighlight.frame then return end
    
    -- Use TOOLTIP
    local frame = CreateFrame("Frame", "UIEssentialsCursorHighlight", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(100)
    frame:SetWidth(CURSOR_SIZE)
    frame:SetHeight(CURSOR_SIZE)
    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:Hide()
    
    -- Create solid filled square
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(unpack(CURSOR_COLOR))
    fill:SetAllPoints(frame)
    
    -- Cache scale and track last position to avoid unnecessary updates
    frame.cachedScale = UIParent:GetEffectiveScale()
    frame.lastX = 0
    frame.lastY = 0
    
    CursorHighlight.frame = frame
end

function CursorHighlight.CreateStarSurgeModel()
    if CursorHighlight.modelFrame then 
        -- Reset the model if it already exists
        CursorHighlight.modelFrame:ClearModel()
        CursorHighlight.modelFrame:SetModel(STAR_SURGE_MODEL_ID)
        CursorHighlight.modelFrame:SetAlpha(STAR_SURGE_ALPHA)
        return 
    end
    
    -- Create model frame
    local modelFrame = CreateFrame("PlayerModel", "UIEssentialsStarSurge", UIParent)
    modelFrame:SetFrameStrata("TOOLTIP")
    modelFrame:SetFrameLevel(100)
    modelFrame:SetAllPoints(UIParent)
    modelFrame:EnableMouse(false)
    modelFrame:Hide()
    
    -- Set up the Star Surge model
    modelFrame:SetModel(STAR_SURGE_MODEL_ID)
    modelFrame:SetAlpha(STAR_SURGE_ALPHA)
    
    CursorHighlight.modelFrame = modelFrame
end

function CursorHighlight.StopTracking()
    if CursorHighlight.frame then
        CursorHighlight.frame:Hide()
        CursorHighlight.frame:SetScript("OnUpdate", nil)
    end
    if CursorHighlight.modelFrame then
        CursorHighlight.modelFrame:Hide()
        CursorHighlight.modelFrame:SetScript("OnUpdate", nil)
    end
    if CursorHighlight.scaleTicker then
        CursorHighlight.scaleTicker:Cancel()
        CursorHighlight.scaleTicker = nil
    end
end

function CursorHighlight.StartTrackingSquare()
    CursorHighlight.CreateHighlightFrame()
    local frame = CursorHighlight.frame
    local uiParent = UIParent
    local cachedScale = frame.cachedScale
    local updateThrottle = 0
    
    frame:Show()
    frame:SetScript("OnUpdate", function(self, elapsed)
        -- Hide during combat for performance
        if InCombatLockdown() then
            self:Hide()
            return
        end
        
        -- Throttle updates: only update every 2 frames (30fps instead of 60fps)
        updateThrottle = updateThrottle + 1
        if updateThrottle < 2 then
            return
        end
        updateThrottle = 0
        
        if not self:IsShown() then
            self:Show()
        end
        
        local x, y = GetCursorPosition()
        x, y = x / cachedScale, y / cachedScale
        if x ~= self.lastX or y ~= self.lastY then
            self.lastX, self.lastY = x, y
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", uiParent, "BOTTOMLEFT", x, y)
        end
    end)
    
    if not CursorHighlight.scaleTicker then
        CursorHighlight.scaleTicker = C_Timer.NewTicker(SCALE_UPDATE_INTERVAL, function()
            if frame and frame:IsShown() then
                local newScale = UIParent:GetEffectiveScale()
                if newScale ~= cachedScale then
                    cachedScale = newScale
                    frame.cachedScale = cachedScale
                    frame.lastX, frame.lastY = 0, 0
                end
            else
                if CursorHighlight.scaleTicker then
                    CursorHighlight.scaleTicker:Cancel()
                    CursorHighlight.scaleTicker = nil
                end
            end
        end)
    end
end

function CursorHighlight.StartTrackingStarSurge()
    if CursorHighlight.frame then
        CursorHighlight.frame:Hide()
        CursorHighlight.frame:SetScript("OnUpdate", nil)
    end
    
    CursorHighlight.CreateStarSurgeModel()
    local modelFrame = CursorHighlight.modelFrame
    local cachedScale = UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local screenHypotenuse = math.sqrt(screenWidth * screenWidth + screenHeight * screenHeight)
    local posVector = CreateVector3D(0, 0, 0)
    local rotVector = CreateVector3D(0, 315, 0)
    local lastX, lastY = nil, nil
    local isMoving = false
    
    -- Keep frame shown but use alpha to control visibility (new UI system may need frame to be shown)
    modelFrame:Show()
    modelFrame:SetAlpha(0) -- Start invisible
    
    local updateThrottle = 0  -- Throttle updates to every 3 frames for better performance
    modelFrame:SetScript("OnUpdate", function(self, elapsed)
        -- Hide during combat for performance
        if InCombatLockdown() then
            if self:GetAlpha() > 0 then
                self:SetAlpha(0)
                isMoving = false
            end
            return
        end
        
        -- Throttle updates: only update every 3 frames (~20fps) for expensive model transforms
        updateThrottle = updateThrottle + 1
        if updateThrottle < 3 then
            return
        end
        updateThrottle = 0
        
        local x, y = GetCursorPosition()
        x, y = x / cachedScale, y / cachedScale
        
        -- Initialize last position on first update
        if lastX == nil or lastY == nil then
            lastX, lastY = x, y
            return
        end
        
        -- Check if cursor moved (with threshold to avoid tiny movements)
        local dx = x - lastX
        local dy = y - lastY
        local distanceSq = dx * dx + dy * dy
        local moved = distanceSq > (STAR_SURGE_MOVEMENT_THRESHOLD * STAR_SURGE_MOVEMENT_THRESHOLD)
        
        -- Only update transform if cursor moved significantly
        if moved then
            -- Always update position when moving
            local offsetX = x + STAR_SURGE_OFFSET_X
            local offsetY = y + STAR_SURGE_OFFSET_Y
            posVector:SetXYZ(offsetX / screenHypotenuse, offsetY / screenHypotenuse, 0)
            modelFrame:SetTransform(posVector, rotVector, STAR_SURGE_SCALE)
            
            -- Cursor is moving - show the trail
            if not isMoving then
                modelFrame:SetAlpha(STAR_SURGE_ALPHA)
                isMoving = true
            end
        else
            -- Cursor stopped - hide the trail
            if isMoving then
                modelFrame:SetAlpha(0)
                isMoving = false
            end
        end
        
        -- Always update last position
        lastX, lastY = x, y
        
        -- Update scale cache periodically
        local currentTime = GetTime()
        if not self.lastScaleCheckTime or (currentTime - self.lastScaleCheckTime) >= 0.5 then
            local newScale = UIParent:GetEffectiveScale()
            if newScale ~= cachedScale then
                cachedScale = newScale
                screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
                screenHypotenuse = math.sqrt(screenWidth * screenWidth + screenHeight * screenHeight)
            end
            self.lastScaleCheckTime = currentTime
        end
    end)
end

function CursorHighlight.StartTracking()
    if not SettingsManager:Get("showCursorHighlight") then
        CursorHighlight.StopTracking()
        return
    end
    local style = SettingsManager:Get("cursorStyle") or "square"
    if style == "starsurge" then
        CursorHighlight.StartTrackingStarSurge()
    else
        CursorHighlight.StartTrackingSquare()
    end
end

function CursorHighlight.Initialize()
    if SettingsManager:Get("showCursorHighlight") then
        CursorHighlight.StartTracking()
    end
end

-- ========================================
-- OPTIONS PANEL MODULE
-- ========================================
local OptionsPanel = {}
OptionsPanel.frame = nil

-- UI Constants
local PANEL_WIDTH = 500
local PANEL_HEIGHT = 350
local COLUMN_WIDTH = 230
local COLUMN_SPACING = 20
local BEIGE_BG = {0.85, 0.82, 0.75, 0.95}
local BEIGE_BORDER = {0.65, 0.60, 0.50, 1.0}

-- Text Colors
local COLOR_TITLE = {0.15, 0.10, 0.05, 1.0}
local COLOR_VERSION = {0.35, 0.28, 0.20, 1.0}
local COLOR_HEADER = {0.25, 0.18, 0.12, 1.0}
local COLOR_LABEL = {1.0, 0.85, 0.0, 1.0}
local COLOR_HINT = {0.45, 0.35, 0.25, 1.0}

-- Helper function to create a checkbox
local function CreateCheckbox(parent, label, tooltip, x, y, getFunc, setFunc)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", x, y)
    check:SetSize(22, 22)
    
    local labelText = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("LEFT", check, "RIGHT", 3, 0)
    labelText:SetText(label)
    labelText:SetTextColor(unpack(COLOR_LABEL))
    
    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if setFunc then setFunc(checked) end
    end)
    
    check:SetScript("OnEnter", function(self)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    
    check:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Update checkbox state
    check.UpdateState = function()
        local checked = getFunc and getFunc() or false
        check:SetChecked(checked)
    end
    
    check.UpdateState()
    return check
end

-- Helper function to create a section header
local function CreateSectionHeader(parent, text, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", x, y)
    header:SetTextColor(unpack(COLOR_HEADER))
    header:SetText(text)
    return header
end

-- Helper function to create a dropdown menu
local function CreateDropdown(parent, label, tooltip, x, y, options, getFunc, setFunc)
    -- Label
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("TOPLEFT", x, y)
    labelText:SetText(label)
    labelText:SetTextColor(unpack(COLOR_LABEL))
    
    -- Dropdown button
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", -15, -5)
    
    -- Initialize dropdown
    UIDropDownMenu_SetWidth(dropdown, 150)
    UIDropDownMenu_SetText(dropdown, options[getFunc()] or options[1])
    
    -- Dropdown menu function
    local function InitializeDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for value, text in pairs(options) do
            info.text = text
            info.value = value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, value)
                UIDropDownMenu_SetText(dropdown, text)
                if setFunc then setFunc(value) end
            end
            info.checked = (getFunc() == value)
            UIDropDownMenu_AddButton(info, level)
        end
    end
    
    UIDropDownMenu_Initialize(dropdown, InitializeDropdown)
    
    -- Tooltip
    if tooltip then
        dropdown:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        dropdown:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    
    -- Update function
    dropdown.UpdateState = function()
        local currentValue = getFunc()
        UIDropDownMenu_SetSelectedValue(dropdown, currentValue)
        UIDropDownMenu_SetText(dropdown, options[currentValue] or options[1])
    end
    
    return dropdown
end

function OptionsPanel.CreatePanel()
    if OptionsPanel.frame then return end
    
    -- Create main frame with backdrop template
    local frame = CreateFrame("Frame", "UIEssentialsOptionsPanel", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(500, -500, -300, 300)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    
    -- Make it a system frame (ESC closes it)
    table.insert(UISpecialFrames, "UIEssentialsOptionsPanel")
    
    -- Border with backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(unpack(BEIGE_BG))
    frame:SetBackdropBorderColor(unpack(BEIGE_BORDER))
    
    -- Drag handling
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("UIEssentials")
    title:SetTextColor(unpack(COLOR_TITLE))
    
    -- Version
    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    version:SetText("Version 2.4")
    version:SetTextColor(unpack(COLOR_VERSION))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 12, -45)
    content:SetPoint("BOTTOMRIGHT", -12, 50)
    
    -- Left column
    local leftColumn = CreateFrame("Frame", nil, content)
    leftColumn:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -5)
    leftColumn:SetWidth(COLUMN_WIDTH)
    leftColumn:SetHeight(1)
    
    -- Right column
    local rightColumn = CreateFrame("Frame", nil, content)
    rightColumn:SetPoint("TOPLEFT", leftColumn, "TOPRIGHT", COLUMN_SPACING, 0)
    rightColumn:SetWidth(COLUMN_WIDTH)
    rightColumn:SetHeight(1)
    
    -- LEFT COLUMN: Tooltip Features Section
    local yOffset = 0
    CreateSectionHeader(leftColumn, "Tooltip Features", 0, yOffset)
    yOffset = yOffset - 18
    
    local enableTooltips = CreateCheckbox(leftColumn, "Show targeting info in tooltips", 
        "Display who is targeting what in unit tooltips", 8, yOffset,
        function() return SettingsManager:Get("enableTooltips") end,
        function(val) SettingsManager:Set("enableTooltips", val) end
    )
    yOffset = yOffset - 22
    
    -- LEFT COLUMN: Character Features Section
    yOffset = yOffset - 8
    CreateSectionHeader(leftColumn, "Character Features", 0, yOffset)
    yOffset = yOffset - 18
    
    local itemLevelDecimals = CreateCheckbox(leftColumn, "Show item level decimals", 
        "Display item level with decimal precision in character frame", 8, yOffset,
        function() return SettingsManager:Get("showItemLevelDecimals") end,
        function(val) SettingsManager:Set("showItemLevelDecimals", val) end
    )
    yOffset = yOffset - 22
    
    -- LEFT COLUMN: UI Features Section
    yOffset = yOffset - 8
    CreateSectionHeader(leftColumn, "UI Features", 0, yOffset)
    yOffset = yOffset - 18
    
    local cursorHighlight = CreateCheckbox(leftColumn, "Show cursor highlight", 
        "Display a visual indicator at your cursor position", 8, yOffset,
        function() return SettingsManager:Get("showCursorHighlight") end,
        function(val) 
            SettingsManager:Set("showCursorHighlight", val)
            if val then
                CursorHighlight.StartTracking()
            else
                CursorHighlight.StopTracking()
            end
        end
    )
    yOffset = yOffset - 22
    
    -- LEFT COLUMN: Cursor style dropdown
    local cursorStyleDropdown = CreateDropdown(leftColumn, "Cursor style:", 
        "Choose between a green square or Star Surge trail", 8, yOffset,
        {square = "Green Square", starsurge = "Star Surge"},
        function() return SettingsManager:Get("cursorStyle") or "square" end,
        function(val)
            SettingsManager:Set("cursorStyle", val)
            if SettingsManager:Get("showCursorHighlight") then
                CursorHighlight.StartTracking()
            end
        end
    )
    
    -- RIGHT COLUMN: Realm Name Removal Section
    yOffset = 0
    CreateSectionHeader(rightColumn, "Realm Name Removal", 0, yOffset)
    yOffset = yOffset - 18
    
    local hideRealmRaid = CreateCheckbox(rightColumn, "Hide realm names in raid frames", 
        "Remove realm names from raid unit frames", 8, yOffset,
        function() return SettingsManager:Get("hideRealmRaid") end,
        function(val) SettingsManager:Set("hideRealmRaid", val) end
    )
    yOffset = yOffset - 22
    
    local hideRealmParty = CreateCheckbox(rightColumn, "Hide realm names in party frames", 
        "Remove realm names from party unit frames", 8, yOffset,
        function() return SettingsManager:Get("hideRealmParty") end,
        function(val) SettingsManager:Set("hideRealmParty", val) end
    )
    yOffset = yOffset - 22
    
    -- RIGHT COLUMN: Cutscene Skipper Section
    yOffset = yOffset - 8
    CreateSectionHeader(rightColumn, "Cutscene Features", 0, yOffset)
    yOffset = yOffset - 18
    
    local autoSkipCutscenes = CreateCheckbox(rightColumn, "Auto skip all cutscenes", 
        "Automatically skip all cutscenes and movies, regardless of whether you've seen them", 8, yOffset,
        function() return SettingsManager:Get("autoSkipCutscenes") end,
        function(val) 
            SettingsManager:Set("autoSkipCutscenes", val)
            if val then
                CutsceneSkipper.Enable()
            else
                CutsceneSkipper.Disable()
            end
        end
    )
    yOffset = yOffset - 22
    
    -- RIGHT COLUMN: Item Comparison Section
    yOffset = yOffset - 8
    CreateSectionHeader(rightColumn, "Item Comparison", 0, yOffset)
    yOffset = yOffset - 18
    
    local disableAutoCompare = CreateCheckbox(rightColumn, "Disable auto-comparison (Shift to compare)", 
        "Restore old behavior: Hold Shift to compare gear instead of automatic comparison", 8, yOffset,
        function() return SettingsManager:Get("disableAutoCompare") end,
        function(val) 
            SettingsManager:Set("disableAutoCompare", val)
            AutoCompareDisabler.ApplySetting()
        end
    )
    
    -- Reload button (centered at bottom)
    local reloadBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reloadBtn:SetSize(90, 26)
    reloadBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    reloadBtn:SetText("Reload UI")
    reloadBtn:SetScript("OnClick", ReloadUI)
    
    local reloadText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reloadText:SetPoint("BOTTOM", reloadBtn, "TOP", 0, 4)
    reloadText:SetText("Please /reload to apply ANY changes")
    reloadText:SetTextColor(unpack(COLOR_HINT))
    
    -- Store checkboxes and dropdowns for updates
    frame.checkboxes = {
        enableTooltips = enableTooltips,
        itemLevelDecimals = itemLevelDecimals,
        cursorHighlight = cursorHighlight,
        cursorStyle = cursorStyleDropdown,
        hideRealmRaid = hideRealmRaid,
        hideRealmParty = hideRealmParty,
        autoSkipCutscenes = autoSkipCutscenes,
        disableAutoCompare = disableAutoCompare
    }
    
    -- Update function
    frame.UpdateCheckboxes = function()
        for _, checkbox in pairs(frame.checkboxes) do
            if checkbox.UpdateState then
                checkbox:UpdateState()
            end
        end
    end
    
    -- Center on screen when shown
    frame:SetScript("OnShow", function(self)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        self:UpdateCheckboxes()
    end)
    
    OptionsPanel.frame = frame
end

function OptionsPanel.Show()
    OptionsPanel.CreatePanel()
    if OptionsPanel.frame then
        OptionsPanel.frame:Show()
    end
end

function OptionsPanel.Initialize()
    -- Create panel but don't show it yet
    OptionsPanel.CreatePanel()
    return true
end

-- ========================================
-- SLASH COMMANDS
-- ========================================
local function OpenOptionsPanel()
    OptionsPanel.Show()
end

local function TestItemLevel()
    if not UnitExists("mouseover") then
        print("|cffff6600UIEssentials:|r No unit under mouse")
        return
    end
    
    local name = UnitName("mouseover")
    local isPlayer = UnitIsPlayer("mouseover")
    local canInspect = CanInspect("mouseover")
    local inRange = CheckInteractDistance("mouseover", 1)
    local guid = UnitGUID("mouseover")
    
    print("|cffff6600UIEssentials Debug:|r")
    print("  Name: " .. (name or "nil"))
    print("  Is Player: " .. tostring(isPlayer))
    print("  Can Inspect: " .. tostring(canInspect))
    print("  In Range: " .. tostring(inRange))
    print("  GUID: " .. (guid or "nil"))
    
    if isPlayer then
        -- Request inspection
        if canInspect and inRange then
            NotifyInspect("mouseover")
            print("  Requested inspection...")
            C_Timer.After(1, function()
                if UnitExists("mouseover") and UnitGUID("mouseover") == guid then
                    local ilvl = Utils.GetUnitItemLevel("mouseover")
                    print("  Item Level: " .. (ilvl or "nil"))
                    if ilvl then
                        local color = Utils.GetILvlColor(ilvl)
                        print("  " .. color .. "iLvl: " .. ilvl .. "|r")
                    end
                    ClearInspectPlayer()
                end
            end)
        else
            print("  Cannot inspect (not in range or unit not inspectable)")
        end
    end
end

SlashCmdList.UIESSENTIALS = OpenOptionsPanel
SLASH_UIESSENTIALS1 = "/ue"
SLASH_UIESSENTIALS2 = "/uiessentials"

SlashCmdList.UIESSENTIALS_TEST = TestItemLevel
SLASH_UIESSENTIALS_TEST1 = "/uetest"

-- ========================================
-- ADDON INITIALIZATION
-- ========================================
local function Initialize()
    SettingsManager:Initialize()
    ItemLevelInspector:Initialize()
    TooltipHandler.Initialize()
    RealmNameRemoval.Initialize()
    ItemLevelDecimal.Initialize()
    AutoCompareDisabler.Initialize()
    CursorHighlight.Initialize()
    CutsceneSkipper.Initialize()
    Cache:StartCleanupTimer()
    OptionsPanel.Initialize()
end

-- Register addon loaded event
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if loadedAddonName == addonName then
        Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

