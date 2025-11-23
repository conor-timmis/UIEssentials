-- TargetToolTip
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
}

-- ========================================
-- SETTINGS MODULE
-- ========================================
local Settings = {}

function Settings:Initialize()
    TargetToolTip = TargetToolTip or {}
    
    -- Merge defaults with saved settings
    for key, value in pairs(DEFAULTS) do
        if TargetToolTip[key] == nil then
            TargetToolTip[key] = value
        end
    end
    
    return TargetToolTip
end

function Settings:Get(key)
    return TargetToolTip and TargetToolTip[key]
end

function Settings:Set(key, value)
    if TargetToolTip then
        TargetToolTip[key] = value
    end
end

-- ========================================
-- CACHE MODULE
-- ========================================
local Cache = {}
Cache.data = {}

function Cache:Get(guid)
    local cached = self.data[guid]
    if not cached then return nil end
    
    if GetTime() - cached.timestamp > CONSTANTS.CACHE_TIMEOUT then
        self.data[guid] = nil
        return nil
    end
    
    return cached.data
end

function Cache:Set(guid, data)
    self.data[guid] = {
        data = data,
        timestamp = GetTime()
    }
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
    local frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.timeSinceLastCleanup = (self.timeSinceLastCleanup or 0) + elapsed
        
        if self.timeSinceLastCleanup >= CONSTANTS.CACHE_CLEANUP_INTERVAL then
            Cache:Clean()
            self.timeSinceLastCleanup = 0
        end
    end)
end

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================
local Utils = {}

function Utils.StripRealm(name)
    if not name then return "" end
    return name:match("^([^-]+)") or name
end

function Utils.GetUnitColor(unit)
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
end

function Utils.FindUnitByGUID(guid)
    -- Check common units first (most likely)
    local commonUnits = {"mouseover", "target", "focus"}
    for _, unitToken in ipairs(commonUnits) do
        if UnitGUID(unitToken) == guid then
            return unitToken
        end
    end
    
    -- Check party members
    if IsInGroup() then
        for i = 1, CONSTANTS.MAX_PARTY_MEMBERS do
            local partyUnit = "party" .. i
            if UnitGUID(partyUnit) == guid then
                return partyUnit
            end
        end
    end
    
    -- Check raid members
    if IsInRaid() then
        for i = 1, CONSTANTS.MAX_RAID_MEMBERS do
            local raidUnit = "raid" .. i
            if UnitGUID(raidUnit) == guid then
                return raidUnit
            end
        end
    end
    
    -- Check nameplates
    for i = 1, CONSTANTS.MAX_NAMEPLATES do
        local nameplateUnit = "nameplate" .. i
        if UnitGUID(nameplateUnit) == guid then
            return nameplateUnit
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

-- ========================================
-- TARGETING SCANNER MODULE
-- ========================================
local TargetingScanner = {}

function TargetingScanner.IsUnitTargeting(scanUnit, targetUnit)
    if not UnitExists(scanUnit) then return false end
    
    local scanTarget = scanUnit .. "target"
    return UnitExists(scanTarget) and UnitIsUnit(scanTarget, targetUnit)
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
    local targeters = {}
    
    -- Check party (only if not in raid to avoid duplicates)
    if IsInGroup() and not IsInRaid() then
        TargetingScanner.ScanUnits("party", CONSTANTS.MAX_PARTY_MEMBERS, targetUnit, targeters, false)
    end
    
    -- Check raid
    if IsInRaid() then
        TargetingScanner.ScanUnits("raid", CONSTANTS.MAX_RAID_MEMBERS, targetUnit, targeters, false)
    end
    
    -- Check nameplates (skip in raids for performance)
    if not IsInRaid() then
        TargetingScanner.ScanUnits("nameplate", CONSTANTS.MAX_NAMEPLATES, targetUnit, targeters, true)
    end
    
    return targeters
end

-- ========================================
-- TOOLTIP RENDERER MODULE
-- ========================================
local TooltipRenderer = {}

function TooltipRenderer.RenderTargetLine(targetUnit)
    if UnitIsUnit(targetUnit, "player") then
        return CONSTANTS.COLORS.LABEL .. "Target: |r" .. CONSTANTS.COLORS.ME .. "Me|r"
    end
    
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

function TooltipRenderer.ApplyTooltip(tooltip, targetText, targeterLines)
    if targetText and targetText ~= "" then
        tooltip:AddLine(targetText)
    end
    
    if targeterLines and #targeterLines > 0 then
        tooltip:AddLine(" ")
        for _, line in ipairs(targeterLines) do
            tooltip:AddLine(line)
        end
    end
    
    tooltip:Show()
end

-- ========================================
-- TOOLTIP HANDLER MODULE
-- ========================================
local TooltipHandler = {}

function TooltipHandler.AddTargetInfo(tooltip, data)
    if not data or not data.guid then return end
    if not Settings:Get("enableTooltips") then return end
    
    -- Try cache first
    local cached = Cache:Get(data.guid)
    if cached then
        TooltipRenderer.ApplyTooltip(tooltip, cached.targetText, cached.targeterLines)
        return
    end
    
    -- Find unit
    local unit = Utils.FindUnitByGUID(data.guid)
    if not unit or not UnitExists(unit) then return end
    
    -- Build tooltip data
    local targetText = ""
    local targeterLines = {}
    
    -- Who is this unit targeting?
    local targetUnit = unit .. "target"
    if UnitExists(targetUnit) then
        targetText = TooltipRenderer.RenderTargetLine(targetUnit)
    end
    
    -- Who is targeting this unit?
    local targeters = TargetingScanner.GetUnitsTargeting(unit)
    if #targeters > 0 then
        targeterLines = TooltipRenderer.RenderTargetersList(targeters)
    end
    
    -- Cache for future
    Cache:Set(data.guid, {
        targetText = targetText,
        targeterLines = targeterLines
    })
    
    TooltipRenderer.ApplyTooltip(tooltip, targetText, targeterLines)
end

function TooltipHandler.Initialize()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if tooltip == GameTooltip then
            TooltipHandler.AddTargetInfo(tooltip, data)
        end
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
    if not Settings:Get("hideRealmRaid") then return end
    
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if Utils.MatchesFramePattern(frame:GetName()) then
            RealmNameRemoval.StripRealmFromFrame(frame)
        end
    end)
end

function RealmNameRemoval.InitializePartyFrames()
    if not Settings:Get("hideRealmParty") then return end
    
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
    end
end

function ItemLevelDecimal.Initialize()
    -- Setup hook when character frame is shown
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", ItemLevelDecimal.TrySetupHook)
        
        -- Setup immediately if character frame is already open
        if CharacterFrame:IsShown() then
            ItemLevelDecimal.TrySetupHook()
        end
    end
end

-- ========================================
-- OPTIONS PANEL MODULE
-- ========================================
local OptionsPanel = {}

function OptionsPanel.CreateFontString(parent, font, justify, anchor, relativeTo, relativeAnchor, x, y, text)
    local fs = parent:CreateFontString(nil, 'ARTWORK', font)
    fs:SetJustifyH(justify)
    fs:SetPoint(anchor, relativeTo, relativeAnchor, x, y)
    fs:SetText(text)
    return fs
end

function OptionsPanel.CreateCheckbox(parent, anchor, relativeTo, x, y, label, settingKey)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint(anchor, relativeTo, x, y)
    checkbox.Text:SetText(label)
    checkbox:SetScript("OnClick", function(self)
        Settings:Set(settingKey, self:GetChecked() and true or false)
    end)
    checkbox:SetChecked(Settings:Get(settingKey))
    return checkbox
end

function OptionsPanel.CreateReloadButton(parent, anchor, relativeTo, x, y)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint(anchor, relativeTo, x, y)
    button:SetText("Reload UI")
    button:SetWidth(120)
    button:SetScript("OnClick", ReloadUI)
    return button
end

function OptionsPanel.Initialize()
    local panel = CreateFrame("Frame", "TargetToolTipOptionsPanel", UIParent)
    panel.name = "Target ToolTip"
    
    -- Title and description
    local title = OptionsPanel.CreateFontString(panel, 'GameFontNormalHuge', 'LEFT', 'TOPLEFT', panel, 'TOPLEFT', 16, -16, panel.name)
    local subtitle = OptionsPanel.CreateFontString(panel, 'GameFontNormal', 'LEFT', 'TOPLEFT', title, 'BOTTOMLEFT', 0, -8, 'Configure which features are enabled.')
    local reloadNote = OptionsPanel.CreateFontString(panel, 'GameFontHighlight', 'LEFT', 'TOPLEFT', subtitle, 'BOTTOMLEFT', 0, -4, 'Note: Changes require a UI reload (/reload) to take effect.')
    
    -- Tooltip Features Section
    local tooltipHeader = OptionsPanel.CreateFontString(panel, 'GameFontNormalLarge', 'LEFT', 'TOPLEFT', reloadNote, 'BOTTOMLEFT', 0, -30, 'Tooltip Features')
    local cbTooltips = OptionsPanel.CreateCheckbox(panel, "TOPLEFT", tooltipHeader, 0, -20, "Show targeting information in tooltips", "enableTooltips")
    
    -- Realm Name Removal Section
    local realmHeader = OptionsPanel.CreateFontString(panel, 'GameFontNormalLarge', 'LEFT', 'TOPLEFT', cbTooltips, 'BOTTOMLEFT', 0, -30, 'Realm Name Removal')
    local cbRealmRaid = OptionsPanel.CreateCheckbox(panel, "TOPLEFT", realmHeader, 0, -20, "Remove realm names from raid frames", "hideRealmRaid")
    local cbRealmParty = OptionsPanel.CreateCheckbox(panel, "TOPLEFT", cbRealmRaid, 0, -25, "Remove realm names from party frames", "hideRealmParty")
    
    -- Reload Button
    OptionsPanel.CreateReloadButton(panel, "TOPLEFT", cbRealmParty, 0, -40)
    
    -- Register the panel
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    
    return category:GetID()
end

-- ========================================
-- SLASH COMMANDS
-- ========================================
local categoryID

local function OpenOptionsPanel()
    if categoryID then
        _G.Settings.OpenToCategory(categoryID)
    else
        print("Target ToolTip: Options panel not available.")
    end
end

SlashCmdList.TARGETTOOLTIP = OpenOptionsPanel
SLASH_TARGETTOOLTIP1 = "/tt"
SLASH_TARGETTOOLTIP2 = "/targettooltip"

-- ========================================
-- ADDON INITIALIZATION
-- ========================================
local function Initialize()
    Settings:Initialize()
    TooltipHandler.Initialize()
    RealmNameRemoval.Initialize()
    ItemLevelDecimal.Initialize()
    Cache:StartCleanupTimer()
    categoryID = OptionsPanel.Initialize()
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

