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
        LABEL = "|cffff6600", ME = "|cff00ff00", FRIENDLY = "|cff00ff00",
        NEUTRAL = "|cffffff00", HOSTILE = "|cffff0000", DEFAULT = "|cffffffff"
    },
    ILVL_COLORS = {
        GREY = "|cff9d9d9d", GREEN = "|cff1eff00", BLUE = "|cff0070dd",
        PURPLE = "|cffa335ee", ORANGE = "|cffff8000"
    },
    REALM_FRAME_PATTERNS = {
        "^PartyMemberFrame%d", "^CompactRaidFrame%d",
        "^CompactRaidGroup%dMember%d", "^CompactPartyFrameMember%d"
    }
}

local DEFAULTS = {
    enableTooltips = true, hideRealmRaid = true, hideRealmParty = true,
    showItemLevelDecimals = true, showCursorHighlight = false,
    cursorStyle = "square", autoSkipCutscenes = true, disableAutoCompare = true,
    enableCooldownColors = true
}

-- ========================================
-- SETTINGS MODULE
-- ========================================
local SettingsManager = {}

function SettingsManager:Initialize()
    UIEssentials = UIEssentials or {}
    for key, value in pairs(DEFAULTS) do
        if UIEssentials[key] == nil then UIEssentials[key] = value end
    end
    return UIEssentials
end

function SettingsManager:Get(key)
    return UIEssentials and UIEssentials[key]
end

function SettingsManager:Set(key, value)
    if UIEssentials then UIEssentials[key] = value end
end

-- ========================================
-- CACHE MODULE
-- ========================================
local Cache = {data = {}}

function Cache:Get(guid)
    local success, result = pcall(function()
        local cached = self.data[guid]
        if not cached then return nil end
        if GetTime() - cached.timestamp > CONSTANTS.CACHE_TIMEOUT then
            self.data[guid] = nil
            return nil
        end
        return cached.data
    end)
    return success and result or nil
end

function Cache:Set(guid, data)
    pcall(function()
        self.data[guid] = {data = data, timestamp = GetTime()}
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
    C_Timer.NewTicker(CONSTANTS.CACHE_CLEANUP_INTERVAL, function()
        if not InCombatLockdown() then Cache:Clean() end
    end)
end

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================
local Utils = {}

function Utils.StripRealm(name)
    if not name then return "" end
    local success, result = pcall(function() return name:match("^([^-]+)") or name end)
    return (success and result) or ""
end

function Utils.GetUnitColor(unit)
    local success, result = pcall(function()
        if UnitIsPlayer(unit) then
            local _, class = UnitClass(unit)
            if class and RAID_CLASS_COLORS[class] then
                local c = RAID_CLASS_COLORS[class]
                return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
            end
        else
            local reaction = UnitReaction(unit, "player")
            if reaction then
                if reaction >= 5 then return CONSTANTS.COLORS.FRIENDLY
                elseif reaction == 4 then return CONSTANTS.COLORS.NEUTRAL
                else return CONSTANTS.COLORS.HOSTILE end
            end
        end
        return CONSTANTS.COLORS.DEFAULT
    end)
    return (success and result) or CONSTANTS.COLORS.DEFAULT
end

function Utils.FindUnitByGUID(guid)
    if not guid then return nil end
    local function compareGUID(unitToken)
        if not UnitExists(unitToken) then return false end
        local success, isMatch = pcall(function() return UnitGUID(unitToken) == guid end)
        return success and isMatch
    end
    local function scanUnits(prefix, maxCount)
        for i = 1, maxCount do
            local unit = prefix .. i
            if compareGUID(unit) then return unit end
        end
    end
    for _, unit in ipairs({"mouseover", "target", "focus"}) do
        if compareGUID(unit) then return unit end
    end
    if IsInGroup() and not IsInRaid() then
        local max = math.min(GetNumGroupMembers() or CONSTANTS.MAX_PARTY_MEMBERS, CONSTANTS.MAX_PARTY_MEMBERS)
        local unit = scanUnits("party", max)
        if unit then return unit end
    end
    if IsInRaid() then
        local max = math.min(GetNumGroupMembers() or CONSTANTS.MAX_RAID_MEMBERS, CONSTANTS.MAX_RAID_MEMBERS)
        local unit = scanUnits("raid", max)
        if unit then return unit end
    end
    if C_NamePlate then
        local success, numNameplates = pcall(function()
            if C_NamePlate.GetNumNamePlates then
                return C_NamePlate.GetNumNamePlates()
            end
            return 0
        end)
        if success and numNameplates and numNameplates > 0 then
            local unit = scanUnits("nameplate", math.min(numNameplates, CONSTANTS.MAX_NAMEPLATES))
            if unit then return unit end
        end
    end
    return nil
end

function Utils.MatchesFramePattern(frameName)
    if not frameName then return false end
    for _, pattern in ipairs(CONSTANTS.REALM_FRAME_PATTERNS) do
        if frameName:match(pattern) then return true end
    end
    return false
end

function Utils.GetILvlColor(ilvl)
    if not ilvl then return CONSTANTS.ILVL_COLORS.GREY end
    if ilvl >= 265 then return CONSTANTS.ILVL_COLORS.ORANGE end
    if ilvl >= 250 then return CONSTANTS.ILVL_COLORS.PURPLE end
    if ilvl >= 235 then return CONSTANTS.ILVL_COLORS.BLUE end
    if ilvl >= 220 then return CONSTANTS.ILVL_COLORS.GREEN end
    return CONSTANTS.ILVL_COLORS.GREY
end

function Utils.GetUnitItemLevel(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    if UnitIsUnit(unit, "player") then
        local _, avg = GetAverageItemLevel()
        return avg and math.floor(avg) or nil
    end
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
        if ilvl and ilvl > 0 then return math.floor(ilvl) end
    end
    local total, count = 0, 0
    local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}
    for _, slotId in ipairs(slots) do
        local itemLink = GetInventoryItemLink(unit, slotId)
        if itemLink then
            local itemLevel = GetDetailedItemLevelInfo(itemLink)
            if itemLevel and itemLevel > 0 and itemLevel < 1000 then
                total, count = total + itemLevel, count + 1
            end
        end
    end
    return (count >= 8) and math.floor(total / count) or nil
end

-- ========================================
-- ITEM LEVEL INSPECTOR MODULE
-- ========================================
local ItemLevelInspector = {cache = {}}

function ItemLevelInspector:GetItemLevel(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    if UnitIsUnit(unit, "player") then return Utils.GetUnitItemLevel(unit) end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local cached = self.cache[guid]
    if cached and (GetTime() - cached.time) < 300 then return cached.ilvl end
    local ilvl = Utils.GetUnitItemLevel(unit)
    if (not ilvl or ilvl == 0) and CanInspect(unit) and CheckInteractDistance(unit, 1) then
        NotifyInspect(unit)
    end
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
        local unit = Utils.FindUnitByGUID(guid)
        if unit then
            local ilvl = Utils.GetUnitItemLevel(unit)
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
    local success, isMatch = pcall(function()
        return UnitIsUnit(scanTarget, targetUnit) and "yes" or "no"
    end)
    return success and isMatch == "yes"
end

function TargetingScanner.AddTargeter(scanUnit, targeters, checkDuplicates)
    local name = UnitName(scanUnit)
    if not name then return end
    name = Utils.StripRealm(name)
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
    if not targetUnit or not UnitExists(targetUnit) then return {} end
    local targeters = {}
    if TargetingScanner.IsUnitTargeting("player", targetUnit) then
        TargetingScanner.AddTargeter("player", targeters, false)
    end
    if IsInGroup() and not IsInRaid() then
        TargetingScanner.ScanUnits("party", CONSTANTS.MAX_PARTY_MEMBERS, targetUnit, targeters, true)
    end
    if IsInRaid() then
        local max = math.min(GetNumGroupMembers() or CONSTANTS.MAX_RAID_MEMBERS, CONSTANTS.MAX_RAID_MEMBERS)
        TargetingScanner.ScanUnits("raid", max, targetUnit, targeters, true)
    end
    if not IsInRaid() then
        local numNameplates = C_NamePlate and C_NamePlate.GetNumNamePlates() or 0
        if numNameplates > 0 then
            TargetingScanner.ScanUnits("nameplate", math.min(numNameplates, CONSTANTS.MAX_NAMEPLATES), targetUnit, targeters, true)
        end
    end
    return targeters
end

-- ========================================
-- TOOLTIP RENDERER MODULE
-- ========================================
local TooltipRenderer = {}

function TooltipRenderer.RenderTargetLine(targetUnit)
    local success, result = pcall(function()
        if UnitIsUnit(targetUnit, "player") then
            return CONSTANTS.COLORS.LABEL .. "Target: |r" .. CONSTANTS.COLORS.ME .. "Me|r"
        end
    end)
    if success and result then return result end
    local targetName = UnitName(targetUnit)
    if not targetName then return "" end
    return CONSTANTS.COLORS.LABEL .. "Target: |r" .. Utils.GetUnitColor(targetUnit) .. Utils.StripRealm(targetName) .. "|r"
end

function TooltipRenderer.RenderTargetersList(targeters)
    local lines = {}
    table.insert(lines, CONSTANTS.COLORS.LABEL .. (#targeters == 1 and "Targeted by:|r" or "Targeted by " .. #targeters .. " units:|r"))
    for _, targeter in ipairs(targeters) do
        table.insert(lines, "  " .. Utils.GetUnitColor(targeter.unit) .. targeter.name .. "|r")
    end
    return lines
end

function TooltipRenderer.RenderItemLevel(ilvl)
    if not ilvl then return "" end
    return CONSTANTS.COLORS.LABEL .. "iLvl: |r" .. Utils.GetILvlColor(ilvl) .. ilvl .. "|r"
end

function TooltipRenderer.ApplyTooltip(tooltip, ilvlText, targetText, targeterLines)
    if ilvlText and ilvlText ~= "" then pcall(function() tooltip:AddLine(ilvlText) end) end
    if targetText and targetText ~= "" then pcall(function() tooltip:AddLine(targetText) end) end
    if targeterLines and #targeterLines > 0 then
        pcall(function() tooltip:AddLine(" ") end)
        for _, line in ipairs(targeterLines) do pcall(function() tooltip:AddLine(line) end) end
    end
end

-- ========================================
-- TOOLTIP HANDLER MODULE
-- ========================================
local TooltipHandler = {}
TooltipHandler.lastProcessed = {} -- Track last processed GUID and time to prevent duplicates

function TooltipHandler.AddTargetInfo(tooltip, data)
    if not data or not data.guid or not SettingsManager:Get("enableTooltips") then return end
    local currentTime = GetTime()
    local lastProcessed = TooltipHandler.lastProcessed[data.guid]
    if lastProcessed and (currentTime - lastProcessed) < 0.1 then return end
    TooltipHandler.lastProcessed[data.guid] = currentTime
    for guid, timestamp in pairs(TooltipHandler.lastProcessed) do
        if (currentTime - timestamp) > 1.0 then TooltipHandler.lastProcessed[guid] = nil end
    end
    local success = pcall(function()
        local cached = Cache:Get(data.guid)
        if cached then
            TooltipRenderer.ApplyTooltip(tooltip, cached.ilvlText, cached.targetText, cached.targeterLines)
            return
        end
        local unit = Utils.FindUnitByGUID(data.guid)
        if not unit or not UnitExists(unit) then return end
        local ilvlText, targetText, targeterLines = "", "", {}
        if UnitIsPlayer(unit) then
            local ilvl = ItemLevelInspector:GetItemLevel(unit)
            if ilvl then ilvlText = TooltipRenderer.RenderItemLevel(ilvl) end
        end
        local targetUnit = unit .. "target"
        local targetSuccess, targetExists = pcall(function() return UnitExists(targetUnit) end)
        if targetSuccess and targetExists then
            local renderSuccess, renderResult = pcall(function() return TooltipRenderer.RenderTargetLine(targetUnit) end)
            if renderSuccess and renderResult then targetText = renderResult end
        end
        local numRaidMembers = IsInRaid() and GetNumGroupMembers() or 0
        if numRaidMembers < 20 then
            local scanSuccess, targeters = pcall(function() return TargetingScanner.GetUnitsTargeting(unit) end)
            if scanSuccess and targeters and #targeters > 0 then
                targeterLines = TooltipRenderer.RenderTargetersList(targeters)
            end
        end
        Cache:Set(data.guid, {ilvlText = ilvlText, targetText = targetText, targeterLines = targeterLines})
        TooltipRenderer.ApplyTooltip(tooltip, ilvlText, targetText, targeterLines)
    end)
end

function TooltipHandler.Initialize()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if tooltip == GameTooltip and data and data.guid and data.type == Enum.TooltipDataType.Unit then
            pcall(TooltipHandler.AddTargetInfo, tooltip, data)
        end
    end)
    hooksecurefunc(GameTooltip, "SetUnit", function(self, unit)
        if not unit or not UnitExists(unit) or not SettingsManager:Get("enableTooltips") then return end
        local guid = UnitGUID(unit)
        if not guid then return end
        C_Timer.After(0.01, function()

            if GameTooltip:IsShown() and UnitExists(unit) then
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
    if not frame or frame:IsForbidden() or not frame.unit or not frame.name or not UnitIsPlayer(frame.unit) then return end
    local unitName = GetUnitName(frame.unit, true)
    if unitName then frame.name:SetText(unitName:match("[^-]+")) end
end

function RealmNameRemoval.InitializeRaidFrames()
    if not SettingsManager:Get("hideRealmRaid") then return end
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if frame and not frame:IsForbidden() and frame.GetName and Utils.MatchesFramePattern(frame:GetName()) then
            RealmNameRemoval.StripRealmFromFrame(frame)
        end
    end)
end

function RealmNameRemoval.InitializePartyFrames()
    if not SettingsManager:Get("hideRealmParty") then return end
    if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        hooksecurefunc("UnitFrame_Update", function()
            for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                local unitName = GetUnitName(frame.unit, true)
                if unitName then frame.name:SetText(unitName:match("[^-]+")) end
            end
        end)
    elseif WOW_PROJECT_ID == WOW_PROJECT_CLASSIC or WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC then
        hooksecurefunc("UnitFrame_Update", function(frame)
            if frame and not frame:IsForbidden() and frame:GetName() and frame:GetName():match("^PartyMemberFrame%d") and frame.unit and frame.name then
                local unitName = GetUnitName(frame.unit, true)
                if unitName then frame.name:SetText(unitName:match("[^-]+")) end
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
    local frame = CharacterStatsPane and CharacterStatsPane.ItemLevelFrame and CharacterStatsPane.ItemLevelFrame.Value
    if not frame then return end
    local _, avg = GetAverageItemLevel()
    if avg and avg > 0 then
        ItemLevelDecimal.isUpdating = true
        frame:SetText(SettingsManager:Get("showItemLevelDecimals") and string.format("%.2f", avg) or math.floor(avg))
        ItemLevelDecimal.isUpdating = false
    end
end

function ItemLevelDecimal.SetupHook()
    if ItemLevelDecimal.isHooked then return true end
    local frame = CharacterStatsPane and CharacterStatsPane.ItemLevelFrame and CharacterStatsPane.ItemLevelFrame.Value
    if not frame then return false end
    hooksecurefunc(frame, "SetText", function(self, text)
        if not SettingsManager:Get("showItemLevelDecimals") or ItemLevelDecimal.isUpdating then return end
        if text and tonumber(text) and not string.find(text, "%.") then
            local _, avg = GetAverageItemLevel()
            if avg and avg > 0 and tonumber(text) == math.floor(avg) then
                ItemLevelDecimal.isUpdating = true
                self:SetText(string.format("%.2f", avg))
                ItemLevelDecimal.isUpdating = false
            end
        end
    end)
    ItemLevelDecimal.isHooked = true
    return true
end

function ItemLevelDecimal.TrySetupHook()
    if not ItemLevelDecimal.SetupHook() then
        C_Timer.After(0.5, ItemLevelDecimal.TrySetupHook)
    elseif CharacterFrame and CharacterFrame:IsShown() then
        ItemLevelDecimal.UpdateDisplay()
    end
end

function ItemLevelDecimal.Initialize()
    if not SettingsManager:Get("showItemLevelDecimals") then return end
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", function()
            ItemLevelDecimal.TrySetupHook()
            C_Timer.After(0.1, ItemLevelDecimal.UpdateDisplay)
        end)
        if CharacterFrame:IsShown() then ItemLevelDecimal.TrySetupHook() end
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
    if CutsceneSkipper.skipTimer then
        CutsceneSkipper.skipTimer:Cancel()
        CutsceneSkipper.skipTimer = nil
    end
    CutsceneSkipper.skipTimer = C_Timer.NewTimer(0.1, function()
        if C_Movie and C_Movie.IsPlayingMovie and C_Movie.IsPlayingMovie() and C_Movie.StopMovie then
            C_Movie.StopMovie()
        end
        if CinematicFrame and CinematicFrame:IsShown() then
            if CinematicFrame_CancelCinematic then CinematicFrame_CancelCinematic() else CinematicFrame:Hide() end
        end
        if MovieFrame and MovieFrame:IsShown() then
            if MovieFrame.CloseDialog then MovieFrame.CloseDialog:Click()
            elseif GameMovieFinished then GameMovieFinished() else MovieFrame:Hide() end
        end
        CutsceneSkipper.skipTimer = nil
    end)
end

function CutsceneSkipper.Enable()
    if CutsceneSkipper.isInitialized then return end
    if not CutsceneSkipper.monitorFrame then CutsceneSkipper.monitorFrame = CreateFrame("Frame") end
    local f = CutsceneSkipper.monitorFrame
    f:RegisterEvent("PLAY_MOVIE")
    f:RegisterEvent("CINEMATIC_START")
    f:SetScript("OnEvent", function(self, event) CutsceneSkipper.SkipCutscene() end)
    if MovieFrame and not CutsceneSkipper.movieFrameHooked then
        MovieFrame:HookScript("OnShow", CutsceneSkipper.SkipCutscene)
        CutsceneSkipper.movieFrameHooked = true
    end
    if CinematicFrame and not CutsceneSkipper.cinematicFrameHooked then
        CinematicFrame:HookScript("OnShow", CutsceneSkipper.SkipCutscene)
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
    if SettingsManager:Get("autoSkipCutscenes") then CutsceneSkipper.Enable() else CutsceneSkipper.Disable() end
end

-- ========================================
-- AUTO-COMPARE DISABLER MODULE
-- ========================================
local AutoCompareDisabler = {}

function AutoCompareDisabler.ApplySetting()
    SetCVar("alwaysCompareItems", SettingsManager:Get("disableAutoCompare") and "0" or "1")
end

function AutoCompareDisabler.Initialize()
    AutoCompareDisabler.ApplySetting()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", AutoCompareDisabler.ApplySetting)
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
    local frame = CreateFrame("Frame", "UIEssentialsCursorHighlight", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(100)
    frame:SetSize(CURSOR_SIZE, CURSOR_SIZE)
    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:Hide()
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(unpack(CURSOR_COLOR))
    fill:SetAllPoints(frame)
    frame.cachedScale = UIParent:GetEffectiveScale()
    frame.lastX, frame.lastY = 0, 0
    CursorHighlight.frame = frame
end

function CursorHighlight.CreateStarSurgeModel()
    if CursorHighlight.modelFrame then
        CursorHighlight.modelFrame:ClearModel()
        CursorHighlight.modelFrame:SetModel(STAR_SURGE_MODEL_ID)
        CursorHighlight.modelFrame:SetAlpha(STAR_SURGE_ALPHA)
        return
    end
    local modelFrame = CreateFrame("PlayerModel", "UIEssentialsStarSurge", UIParent)
    modelFrame:SetFrameStrata("TOOLTIP")
    modelFrame:SetFrameLevel(100)
    modelFrame:SetAllPoints(UIParent)
    modelFrame:EnableMouse(false)
    modelFrame:Hide()
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
    local frame, uiParent, cachedScale, updateThrottle = CursorHighlight.frame, UIParent, CursorHighlight.frame.cachedScale, 0
    frame:Show()
    frame:SetScript("OnUpdate", function(self, elapsed)
        if InCombatLockdown() then self:Hide() return end
        updateThrottle = updateThrottle + 1
        if updateThrottle < 2 then return end
        updateThrottle = 0
        if not self:IsShown() then self:Show() end
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
                    cachedScale, frame.cachedScale = newScale, newScale
                    frame.lastX, frame.lastY = 0, 0
                end
            elseif CursorHighlight.scaleTicker then
                CursorHighlight.scaleTicker:Cancel()
                CursorHighlight.scaleTicker = nil
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
    local posVector, rotVector = CreateVector3D(0, 0, 0), CreateVector3D(0, 315, 0)
    local lastX, lastY, isMoving, updateThrottle = nil, nil, false, 0
    modelFrame:Show()
    modelFrame:SetAlpha(0)
    modelFrame:SetScript("OnUpdate", function(self, elapsed)
        if InCombatLockdown() then
            if self:GetAlpha() > 0 then self:SetAlpha(0) isMoving = false end
            return
        end
        updateThrottle = updateThrottle + 1
        if updateThrottle < 3 then return end
        updateThrottle = 0
        local x, y = GetCursorPosition()
        x, y = x / cachedScale, y / cachedScale
        if lastX == nil or lastY == nil then lastX, lastY = x, y return end
        local dx, dy = x - lastX, y - lastY
        local moved = (dx * dx + dy * dy) > (STAR_SURGE_MOVEMENT_THRESHOLD * STAR_SURGE_MOVEMENT_THRESHOLD)
        if moved then
            posVector:SetXYZ((x + STAR_SURGE_OFFSET_X) / screenHypotenuse, (y + STAR_SURGE_OFFSET_Y) / screenHypotenuse, 0)
            modelFrame:SetTransform(posVector, rotVector, STAR_SURGE_SCALE)
            if not isMoving then modelFrame:SetAlpha(STAR_SURGE_ALPHA) isMoving = true end
        elseif isMoving then
            modelFrame:SetAlpha(0)
            isMoving = false
        end
        lastX, lastY = x, y
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
    if SettingsManager:Get("cursorStyle") == "starsurge" then
        CursorHighlight.StartTrackingStarSurge()
    else
        CursorHighlight.StartTrackingSquare()
    end
end

function CursorHighlight.Initialize()
    if SettingsManager:Get("showCursorHighlight") then CursorHighlight.StartTracking() end
end

-- ========================================
-- OPTIONS PANEL MODULE
-- ========================================
local OptionsPanel = {}
OptionsPanel.frame = nil

-- UI Constants
local PANEL_WIDTH = 520
local PANEL_HEIGHT = 380
local COLUMN_WIDTH = 240
local COLUMN_SPACING = 20
local MODERN_BG = {0.12, 0.12, 0.14, 0.98}
local MODERN_BORDER = {0.25, 0.25, 0.28, 1.0}

-- Text Colors
local COLOR_TITLE = {0.95, 0.95, 0.95, 1.0}
local COLOR_VERSION = {0.7, 0.7, 0.7, 1.0}
local COLOR_HEADER = {0.85, 0.85, 0.85, 1.0}
local COLOR_LABEL = {0.9, 0.9, 0.9, 1.0}
local COLOR_HINT = {0.65, 0.65, 0.65, 1.0}

local function CreateCheckbox(parent, label, tooltip, x, y, getFunc, setFunc)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetPoint("TOPLEFT", x, y)
    check:SetSize(20, 20)
    
    local bg = check:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
    check.bg = bg
    
    local border = check:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.4, 0.4, 0.4, 1.0)
    check.border = border
    
    local checkmark = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkmark:SetPoint("CENTER")
    checkmark:SetText("✓")
    checkmark:SetTextColor(0.2, 0.8, 0.2, 1.0)
    checkmark:Hide()
    check.checkmark = checkmark
    
    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if checked then
            self.bg:SetColorTexture(0.15, 0.3, 0.15, 1.0)
            self.border:SetColorTexture(0.3, 0.6, 0.3, 1.0)
            self.checkmark:Show()
        else
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
            self.border:SetColorTexture(0.4, 0.4, 0.4, 1.0)
            self.checkmark:Hide()
        end
        if setFunc then setFunc(checked) end
    end)
    
    check:SetScript("OnEnter", function(self)
        if not self:GetChecked() then
            self.bg:SetColorTexture(0.25, 0.25, 0.25, 1.0)
            self.border:SetColorTexture(0.5, 0.5, 0.5, 1.0)
        end
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    
    check:SetScript("OnLeave", function(self)
        if not self:GetChecked() then
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
            self.border:SetColorTexture(0.4, 0.4, 0.4, 1.0)
        end
        GameTooltip:Hide()
    end)
    
    local labelText = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("LEFT", check, "RIGHT", 6, 0)
    labelText:SetPoint("RIGHT", check:GetParent(), "RIGHT", -8, 0)
    labelText:SetJustifyH("LEFT")
    labelText:SetWordWrap(false)
    labelText:SetNonSpaceWrap(false)
    labelText:SetText(label)
    labelText:SetTextColor(unpack(COLOR_LABEL))
    
    check.UpdateState = function()
        local checked = (getFunc and getFunc()) or false
        check:SetChecked(checked)
        if checked then
            check.bg:SetColorTexture(0.15, 0.3, 0.15, 1.0)
            check.border:SetColorTexture(0.3, 0.6, 0.3, 1.0)
            check.checkmark:Show()
        else
            check.bg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
            check.border:SetColorTexture(0.4, 0.4, 0.4, 1.0)
            check.checkmark:Hide()
        end
    end
    check:UpdateState()
    return check
end

local function CreateRadioButton(parent, label, tooltip, x, y, value, currentValue, setFunc)
    local radio = CreateFrame("Button", nil, parent)
    radio:SetPoint("TOPLEFT", x, y)
    
    local isSelected = (value == currentValue)
    radio.isSelected = isSelected
    
    local labelText = radio:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("LEFT", radio, "LEFT", 0, 0)
    labelText:SetText(label)
    radio.labelText = labelText
    
    local textWidth = labelText:GetStringWidth()
    radio:SetSize(textWidth + 10, 18)
    
    local function UpdateVisualState()
        if radio.isSelected then
            labelText:SetTextColor(0.3, 0.9, 0.3, 1.0)
        else
            labelText:SetTextColor(unpack(COLOR_LABEL))
        end
    end
    
    radio:SetScript("OnClick", function(self)
        if setFunc then setFunc(value) end
    end)
    
    radio:SetScript("OnEnter", function(self)
        if not radio.isSelected then
            labelText:SetTextColor(0.7, 0.7, 0.7, 1.0)
        end
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    
    radio:SetScript("OnLeave", function(self)
        UpdateVisualState()
        GameTooltip:Hide()
    end)
    
    UpdateVisualState()
    
    radio.UpdateState = function(newCurrentValue)
        radio.isSelected = (value == newCurrentValue)
        UpdateVisualState()
    end
    
    return radio
end

local function CreateSectionHeader(parent, text, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", x, y)
    header:SetTextColor(unpack(COLOR_HEADER))
    header:SetText(text)
    return header
end

local function CreateDropdown(parent, label, tooltip, x, y, options, getFunc, setFunc)
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("TOPLEFT", x, y)
    labelText:SetText(label)
    labelText:SetTextColor(unpack(COLOR_LABEL))
    
    local dropdown = CreateFrame("Button", nil, parent)
    dropdown:SetSize(150, 24)
    dropdown:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -5)
    
    local bg = dropdown:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
    dropdown.bg = bg
    
    local border = dropdown:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.4, 0.4, 0.4, 1.0)
    dropdown.border = border
    
    local text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    text:SetPoint("RIGHT", dropdown, "RIGHT", -24, 0)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(COLOR_LABEL))
    dropdown.text = text
    
    local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
    arrow:SetText("▼")
    arrow:SetTextColor(0.7, 0.7, 0.7, 1.0)
    dropdown.arrow = arrow
    
    local menuFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    menuFrame:SetFrameLevel(1000)
    menuFrame:Hide()
    menuFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    menuFrame:SetBackdropColor(0.15, 0.15, 0.17, 1.0)
    menuFrame:SetBackdropBorderColor(unpack(MODERN_BORDER))
    menuFrame:SetSize(150, 1)
    menuFrame.items = {}
    
    local closeFrame = CreateFrame("Frame", nil, UIParent)
    closeFrame:SetAllPoints()
    closeFrame:EnableMouse(false)
    closeFrame:EnableMouseWheel(false)
    closeFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    closeFrame:SetFrameLevel(menuFrame:GetFrameLevel() - 1)
    closeFrame:SetScript("OnUpdate", nil)
    closeFrame:Hide()
    
    local function EnsureCloseFrameHidden()
        if closeFrame then
            closeFrame:Hide()
            closeFrame:EnableMouse(false)
            closeFrame:SetScript("OnUpdate", nil)
        end
    end
    
    local function UpdateText()
        local currentValue = getFunc()
        dropdown.text:SetText(options[currentValue] or options[1] or "")
    end
    
    local function CreateMenuItem(value, text, yPos)
        local item = CreateFrame("Button", nil, menuFrame)
        item:SetSize(150, 22)
        item:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 0, -yPos)
        
        local itemBg = item:CreateTexture(nil, "BACKGROUND")
        itemBg:SetAllPoints()
        itemBg:SetColorTexture(0.2, 0.2, 0.2, 0)
        item.bg = itemBg
        
        local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemText:SetPoint("LEFT", item, "LEFT", 8, 0)
        itemText:SetText(text)
        itemText:SetTextColor(unpack(COLOR_LABEL))
        
        item:SetScript("OnEnter", function(self)
            itemBg:SetColorTexture(0.3, 0.3, 0.3, 1.0)
        end)
        item:SetScript("OnLeave", function(self)
            itemBg:SetColorTexture(0.2, 0.2, 0.2, 0)
        end)
        item:SetScript("OnClick", function()
            EnsureCloseFrameHidden()
            menuFrame:Hide()
            UpdateText()
            if setFunc then
                C_Timer.After(0.1, function()
                    if setFunc then setFunc(value) end
                end)
            end
        end)
        
        return item
    end
    
    local function CloseMenuOnClickOutside()
        if not menuFrame:IsShown() then return end
        
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        x, y = x / scale, y / scale
        
        local mx, my = menuFrame:GetLeft(), menuFrame:GetTop()
        local mw, mh = menuFrame:GetWidth(), menuFrame:GetHeight()
        local inMenu = (x >= mx and x <= mx + mw and y <= my and y >= my - mh)
        
        local dx, dy = dropdown:GetLeft(), dropdown:GetTop()
        local dw, dh = dropdown:GetWidth(), dropdown:GetHeight()
        local inDropdown = (x >= dx and x <= dx + dw and y <= dy and y >= dy - dh)
        
        if not inMenu and not inDropdown then
            EnsureCloseFrameHidden()
            menuFrame:Hide()
        end
    end
    
    closeFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and menuFrame:IsShown() then
            CloseMenuOnClickOutside()
        end
    end)
    
    closeFrame:SetScript("OnUpdate", function(self)
        if not menuFrame:IsShown() then
            EnsureCloseFrameHidden()
        end
    end)
    
    dropdown:SetScript("OnClick", function(self)
        if menuFrame:IsShown() then
            EnsureCloseFrameHidden()
            menuFrame:Hide()
            return
        end
        
        menuFrame:SetHeight(1)
        for _, item in ipairs(menuFrame.items or {}) do
            if item then
                item:Hide()
                item:SetParent(nil)
            end
        end
        menuFrame.items = {}
        
        local yPos = 0
        local itemCount = 0
        
        for value, text in pairs(options) do
            local item = CreateMenuItem(value, text, yPos)
            table.insert(menuFrame.items, item)
            yPos = yPos + 22
            itemCount = itemCount + 1
        end
        
        menuFrame:SetHeight(itemCount * 22)
        menuFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -1)
        menuFrame:Show()
        closeFrame:Show()
        closeFrame:EnableMouse(true)
        closeFrame:SetScript("OnUpdate", function(self)
            if not menuFrame:IsShown() then
                EnsureCloseFrameHidden()
            end
        end)
    end)
    
    dropdown:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.25, 0.25, 0.25, 1.0)
        border:SetColorTexture(0.5, 0.5, 0.5, 1.0)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    
    dropdown:SetScript("OnLeave", function(self)
        bg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
        border:SetColorTexture(0.4, 0.4, 0.4, 1.0)
        GameTooltip:Hide()
    end)
    
    menuFrame:SetScript("OnHide", function()
        menuFrame:SetHeight(1)
        for _, item in ipairs(menuFrame.items or {}) do
            if item then
                item:Hide()
                item:SetParent(nil)
            end
        end
        menuFrame.items = {}
        EnsureCloseFrameHidden()
    end)
    
    local function CloseMenuOnClickOutside()
        if not menuFrame:IsShown() then return end
        
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        x, y = x / scale, y / scale
        
        local mx, my = menuFrame:GetLeft(), menuFrame:GetTop()
        local mw, mh = menuFrame:GetWidth(), menuFrame:GetHeight()
        local inMenu = (x >= mx and x <= mx + mw and y <= my and y >= my - mh)
        
        local dx, dy = dropdown:GetLeft(), dropdown:GetTop()
        local dw, dh = dropdown:GetWidth(), dropdown:GetHeight()
        local inDropdown = (x >= dx and x <= dx + dw and y <= dy and y >= dy - dh)
        
        if not inMenu and not inDropdown then
            menuFrame:Hide()
        end
    end
    
    local closeFrame = CreateFrame("Frame", nil, UIParent)
    closeFrame:SetAllPoints()
    closeFrame:EnableMouse(true)
    closeFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    closeFrame:SetFrameLevel(menuFrame:GetFrameLevel() - 1)
    closeFrame:Hide()
    
    closeFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            CloseMenuOnClickOutside()
        end
    end)
    
    dropdown:SetScript("OnClick", function(self)
        if menuFrame:IsShown() then
            menuFrame:Hide()
            closeFrame:Hide()
            return
        end
        
        local yPos = 0
        local itemCount = 0
        menuFrame.items = {}
        
        for value, text in pairs(options) do
            local item = CreateMenuItem(value, text, yPos)
            table.insert(menuFrame.items, item)
            yPos = yPos + 22
            itemCount = itemCount + 1
        end
        
        menuFrame:SetHeight(itemCount * 22)
        menuFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -1)
        menuFrame:Show()
        closeFrame:Show()
    end)
    
    dropdown.UpdateState = UpdateText
    UpdateText()
    
    return dropdown
end

function OptionsPanel.CreatePanel()
    if OptionsPanel.frame then return end
    local frame = CreateFrame("Frame", "UIEssentialsOptionsPanel", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(500, -500, -300, 300)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    table.insert(UISpecialFrames, "UIEssentialsOptionsPanel")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropColor(unpack(MODERN_BG))
    frame:SetBackdropBorderColor(unpack(MODERN_BORDER))
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() self:SetUserPlaced(false) end)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("UIEssentials")
    title:SetTextColor(unpack(COLOR_TITLE))
    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    version:SetText("Version 2.4")
    version:SetTextColor(unpack(COLOR_VERSION))
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER")
    closeText:SetText("×")
    closeText:SetTextColor(0.9, 0.9, 0.9, 1.0)
    closeBtn:SetScript("OnEnter", function(self)
        closeBg:SetColorTexture(0.4, 0.15, 0.15, 1.0)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        closeBg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 12, -45)
    content:SetPoint("BOTTOMRIGHT", -12, 50)
    local leftColumn = CreateFrame("Frame", nil, content)
    leftColumn:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -5)
    leftColumn:SetWidth(COLUMN_WIDTH)
    leftColumn:SetHeight(1)
    local rightColumn = CreateFrame("Frame", nil, content)
    rightColumn:SetPoint("TOPLEFT", leftColumn, "TOPRIGHT", COLUMN_SPACING, 0)
    rightColumn:SetWidth(COLUMN_WIDTH)
    rightColumn:SetHeight(1)
    
    local yOffset = 0
    CreateSectionHeader(leftColumn, "Tooltip Features", 0, yOffset)
    local enableTooltips = CreateCheckbox(leftColumn, "Show targeting info in tooltips",
        "Display who is targeting what in unit tooltips", 8, yOffset - 18,
        function() return SettingsManager:Get("enableTooltips") end,
        function(val) SettingsManager:Set("enableTooltips", val) end)
    yOffset = yOffset - 55
    CreateSectionHeader(leftColumn, "Character Features", 0, yOffset)
    local itemLevelDecimals = CreateCheckbox(leftColumn, "Show item level decimals",
        "Display item level with decimal precision in character frame", 8, yOffset - 18,
        function() return SettingsManager:Get("showItemLevelDecimals") end,
        function(val) SettingsManager:Set("showItemLevelDecimals", val) end)
    yOffset = yOffset - 55
    CreateSectionHeader(leftColumn, "UI Features", 0, yOffset)
    local cursorHighlight = CreateCheckbox(leftColumn, "Show cursor highlight",
        "Display a visual indicator at your cursor position", 8, yOffset - 18,
        function() return SettingsManager:Get("showCursorHighlight") end,
        function(val)
            SettingsManager:Set("showCursorHighlight", val)
            if val then CursorHighlight.StartTracking() else CursorHighlight.StopTracking() end
        end)
    local cursorStyleLabel = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cursorStyleLabel:SetPoint("TOPLEFT", 8, yOffset - 55)
    cursorStyleLabel:SetText("Cursor style:")
    cursorStyleLabel:SetTextColor(unpack(COLOR_LABEL))
    
    local cursorStyleRadios = {}
    local function UpdateCursorStyleRadios()
        local currentValue = SettingsManager:Get("cursorStyle") or "square"
        for _, radio in ipairs(cursorStyleRadios) do
            if radio.UpdateState then
                radio:UpdateState(currentValue)
            end
        end
    end
    
    local radio1 = CreateRadioButton(leftColumn, "Green Square",
        "Display a green square at your cursor", 8, yOffset - 73,
        "square", SettingsManager:Get("cursorStyle") or "square",
        function(val)
            SettingsManager:Set("cursorStyle", val)
            UpdateCursorStyleRadios()
            if SettingsManager:Get("showCursorHighlight") then CursorHighlight.StartTracking() end
        end)
    table.insert(cursorStyleRadios, radio1)
    
    local radio2 = CreateRadioButton(leftColumn, "Star Surge",
        "Display a Star Surge trail at your cursor", 8, yOffset - 93,
        "starsurge", SettingsManager:Get("cursorStyle") or "square",
        function(val)
            SettingsManager:Set("cursorStyle", val)
            UpdateCursorStyleRadios()
            if SettingsManager:Get("showCursorHighlight") then CursorHighlight.StartTracking() end
        end)
    table.insert(cursorStyleRadios, radio2)
    
    yOffset = yOffset - 115
    local cooldownColors = CreateCheckbox(leftColumn, "Colorize cooldown timers",
        "Color cooldown text based on remaining time (green/yellow/red)", 8, yOffset - 18,
        function() return SettingsManager:Get("enableCooldownColors") end,
        function(val)
            SettingsManager:Set("enableCooldownColors", val)
            if CooldownColor then
                if val then
                    CooldownColor.Initialize()
                else
                    CooldownColor.Disable()
                end
            end
        end)
    yOffset = 0
    CreateSectionHeader(rightColumn, "Realm Name Removal", 0, yOffset)
    local hideRealmRaid = CreateCheckbox(rightColumn, "Hide realm names in raid frames",
        "Remove realm names from raid unit frames", 8, yOffset - 18,
        function() return SettingsManager:Get("hideRealmRaid") end,
        function(val) SettingsManager:Set("hideRealmRaid", val) end)
    local hideRealmParty = CreateCheckbox(rightColumn, "Hide realm names in party frames",
        "Remove realm names from party unit frames", 8, yOffset - 40,
        function() return SettingsManager:Get("hideRealmParty") end,
        function(val) SettingsManager:Set("hideRealmParty", val) end)
    yOffset = yOffset - 77
    CreateSectionHeader(rightColumn, "Cutscene Features", 0, yOffset)
    local autoSkipCutscenes = CreateCheckbox(rightColumn, "Auto skip all cutscenes",
        "Automatically skip all cutscenes and movies, regardless of whether you've seen them", 8, yOffset - 18,
        function() return SettingsManager:Get("autoSkipCutscenes") end,
        function(val)
            SettingsManager:Set("autoSkipCutscenes", val)
            if val then CutsceneSkipper.Enable() else CutsceneSkipper.Disable() end
        end)
    yOffset = yOffset - 55
    CreateSectionHeader(rightColumn, "Item Comparison", 0, yOffset)
    local disableAutoCompare = CreateCheckbox(rightColumn, "Disable auto-comparison",
        "Hold Shift to compare gear instead of automatic comparison", 8, yOffset - 18,
        function() return SettingsManager:Get("disableAutoCompare") end,
        function(val) SettingsManager:Set("disableAutoCompare", val) AutoCompareDisabler.ApplySetting() end)
    local reloadBtn = CreateFrame("Button", nil, frame)
    reloadBtn:SetSize(120, 36)
    reloadBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    
    local reloadBg = reloadBtn:CreateTexture(nil, "BACKGROUND")
    reloadBg:SetAllPoints()
    reloadBg:SetColorTexture(0.3, 0.18, 0.18, 1.0)
    reloadBtn.bg = reloadBg
    
    local reloadBorder = reloadBtn:CreateTexture(nil, "BORDER")
    reloadBorder:SetAllPoints()
    reloadBorder:SetColorTexture(0.5, 0.3, 0.3, 1.0)
    reloadBtn.border = reloadBorder
    
    local reloadText = reloadBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reloadText:SetPoint("CENTER")
    reloadText:SetText("Reload UI")
    reloadText:SetTextColor(0.95, 0.95, 0.95, 1.0)
    
    reloadBtn:SetScript("OnEnter", function(self)
        reloadBg:SetColorTexture(0.4, 0.25, 0.25, 1.0)
        reloadBorder:SetColorTexture(0.6, 0.4, 0.4, 1.0)
    end)
    
    reloadBtn:SetScript("OnLeave", function(self)
        reloadBg:SetColorTexture(0.3, 0.18, 0.18, 1.0)
        reloadBorder:SetColorTexture(0.5, 0.3, 0.3, 1.0)
    end)
    
    reloadBtn:SetScript("OnMouseDown", function(self)
        reloadBg:SetColorTexture(0.25, 0.15, 0.15, 1.0)
        reloadBorder:SetColorTexture(0.4, 0.25, 0.25, 1.0)
    end)
    
    reloadBtn:SetScript("OnMouseUp", function(self)
        reloadBg:SetColorTexture(0.4, 0.25, 0.25, 1.0)
        reloadBorder:SetColorTexture(0.6, 0.4, 0.4, 1.0)
    end)
    
    reloadBtn:SetScript("OnClick", ReloadUI)
    local reloadText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reloadText:SetPoint("BOTTOM", reloadBtn, "TOP", 0, 4)
    reloadText:SetText("Please /reload to apply ANY changes")
    reloadText:SetTextColor(unpack(COLOR_HINT))
    frame.checkboxes = {
        enableTooltips = enableTooltips, itemLevelDecimals = itemLevelDecimals,
        cursorHighlight = cursorHighlight,
        cooldownColors = cooldownColors,
        hideRealmRaid = hideRealmRaid, hideRealmParty = hideRealmParty,
        autoSkipCutscenes = autoSkipCutscenes, disableAutoCompare = disableAutoCompare
    }
    frame.UpdateCursorStyleRadios = UpdateCursorStyleRadios
    frame.UpdateCheckboxes = function()
        for _, checkbox in pairs(frame.checkboxes) do
            if checkbox.UpdateState then checkbox:UpdateState() end
        end
        if frame.UpdateCursorStyleRadios then
            frame.UpdateCursorStyleRadios()
        end
    end
    frame:SetScript("OnShow", function(self)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        self:UpdateCheckboxes()
    end)
    OptionsPanel.frame = frame
end

function OptionsPanel.Show()
    OptionsPanel.CreatePanel()
    if OptionsPanel.frame then OptionsPanel.frame:Show() end
end

function OptionsPanel.Initialize()
    OptionsPanel.CreatePanel()
    return true
end

-- ========================================
-- SLASH COMMANDS
-- ========================================
SlashCmdList.UIESSENTIALS = OptionsPanel.Show
SLASH_UIESSENTIALS1, SLASH_UIESSENTIALS2 = "/ue", "/uiessentials"

-- ========================================
-- ADDON INITIALIZATION
-- ========================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if loadedAddonName == addonName then
        SettingsManager:Initialize()
        ItemLevelInspector:Initialize()
        TooltipHandler.Initialize()
        RealmNameRemoval.Initialize()
        ItemLevelDecimal.Initialize()
        AutoCompareDisabler.Initialize()
        CursorHighlight.Initialize()
        CutsceneSkipper.Initialize()
        if SettingsManager:Get("enableCooldownColors") and CooldownColor then
            CooldownColor.Initialize()
        end
        Cache:StartCleanupTimer()
        OptionsPanel.Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

