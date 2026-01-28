-- ========================================
-- COOLDOWN COLOR MODULE
-- ========================================
local CooldownColor = {}
CooldownColor.isInitialized = false
CooldownColor.hookedButtons = {}
CooldownColor.cooldownTexts = {}

local scheduledUpdates = {}

local COOLDOWN_COLORS = {
    GREEN = {r = 0.0, g = 1.0, b = 0.0},
    YELLOW = {r = 1.0, g = 0.85, b = 0.0},
    RED = {r = 1.0, g = 0.0, b = 0.0}
}

local function SetTextColorSafe(fontString, r, g, b, a)
    if fontString and not fontString:IsForbidden() then
        pcall(function() fontString:SetTextColor(r, g, b, a or 1.0) end)
    end
end

local function GetTextColorSafe(fontString)
    if fontString and not fontString:IsForbidden() then
        local success, r, g, b, a = pcall(function() return fontString:GetTextColor() end)
        if success and r and g and b then
            return r, g, b, a
        end
    end
    return nil
end

local function GetTextSafe(fontString)
    local success, text = pcall(function() return fontString:GetText() end)
    return success and text or nil
end

local function CleanText(text)
    if not text then return nil end
    local success, result = pcall(function()
        local textStr = tostring(text)
        if not textStr or textStr == "" or textStr == "nil" then return nil end
        return textStr:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    end)
    return success and result or nil
end

local function ParseCooldownTime(text)
    local cleanText = CleanText(text)
    if not cleanText then return nil end
    
    local minutes, seconds = cleanText:match("^(%d+):(%d%d?)$")
    if minutes and seconds then
        local total = tonumber(minutes) * 60 + tonumber(seconds)
        if total and total > 0 and total < 3600 then return total end
    end
    
    local secs = tonumber(cleanText)
    if secs and secs > 0 and secs < 600 then return secs end
    
    return nil
end

local function GetCooldownColor(seconds)
    if not seconds then return nil end
    if seconds <= 8 then return COOLDOWN_COLORS.GREEN end
    if seconds <= 30 then return COOLDOWN_COLORS.YELLOW end
    return COOLDOWN_COLORS.RED
end

local function IsCooldownVisible(cooldownFrame)
    return cooldownFrame and not cooldownFrame:IsForbidden() and 
           cooldownFrame:IsShown() and cooldownFrame:GetAlpha() > 0.3
end

local lastColorCache = {}
local lastTextCache = {}

local function ApplyCooldownColor(cooldownText, button, force)
    if not cooldownText or cooldownText:IsForbidden() then return end
    
    local cooldownFrame = button and button.cooldown
    if not cooldownFrame or cooldownFrame:IsForbidden() then
        local lastColor = lastColorCache[cooldownText]
        if lastColor ~= "white" or force then
            SetTextColorSafe(cooldownText, 1.0, 1.0, 1.0)
            lastColorCache[cooldownText] = "white"
            lastTextCache[cooldownText] = nil
        end
        return
    end
    
    if not cooldownFrame:IsShown() or cooldownFrame:GetAlpha() < 0.3 then
        return
    end
    
    local text = GetTextSafe(cooldownText)
    if not text then return end
    
    local textStr = CleanText(text)
    if not textStr then return end
    
    local lastText = lastTextCache[cooldownText]
    if not force and lastText == textStr then
        return
    end
    lastTextCache[cooldownText] = textStr
    
    local seconds = ParseCooldownTime(textStr)
    if not seconds then return end
    
    local color = GetCooldownColor(seconds)
    if not color then return end
    
    local colorKey = color.r == 0 and "green" or (color.g == 0.85 and "yellow" or "red")
    local lastColor = lastColorCache[cooldownText]
    
    local needsColor = force or lastColor ~= colorKey
    

    if not needsColor then
        local currentR, currentG, currentB = GetTextColorSafe(cooldownText)
        if currentR and currentG and currentB then

            if math.abs(currentR - 1.0) < 0.1 and math.abs(currentG - 1.0) < 0.1 and math.abs(currentB - 1.0) < 0.1 then
                needsColor = true
            end
        end
    end
    
    if needsColor then
        SetTextColorSafe(cooldownText, color.r, color.g, color.b)
        lastColorCache[cooldownText] = colorKey
    end
end

local function IsCooldownTimerText(fontString, cooldownFrame)
    if not fontString or fontString:IsForbidden() then return false end
    if not IsCooldownVisible(cooldownFrame) then return false end
    if fontString:GetParent() ~= cooldownFrame then return false end
    
    local cleanText = CleanText(GetTextSafe(fontString))
    if not cleanText then return false end
    
    local minutes, seconds = cleanText:match("^(%d+):(%d%d?)$")
    if minutes and seconds then return true end
    
    local num = tonumber(cleanText)
    return num and num >= 1 and num < 600
end

local function FindCooldownText(button)
    if not button or not button.cooldown then return nil end
    
    local cooldownFrame = button.cooldown
    if not cooldownFrame or cooldownFrame:IsForbidden() then return nil end
    
    local regions = {cooldownFrame:GetRegions()}
    local candidateFontString = nil
    local bestMatch = nil
    
    local maxRegions = math.min(#regions, 20)
    for i = 1, maxRegions do
        local region = regions[i]
        if region and not region:IsForbidden() and region.GetObjectType and
           region:GetObjectType() == "FontString" and
           region:GetParent() == cooldownFrame then
            local cleanText = CleanText(GetTextSafe(region))
            if cleanText then
                local minutes, seconds = cleanText:match("^(%d+):(%d%d?)$")
                local num = tonumber(cleanText)
                if (minutes and seconds) or (num and num >= 1 and num < 600) then
                    return region
                end
            end
            if not candidateFontString then
                candidateFontString = region
            end
        end
    end

    if candidateFontString then
        return candidateFontString
    end
    
    local children = {cooldownFrame:GetChildren()}
    for i = 1, math.min(#children, 10) do
        local child = children[i]
        if child and not child:IsForbidden() and child.GetObjectType and
           child:GetObjectType() == "FontString" then
            return child
        end
    end
    
    return nil
end

local function CleanupInvalidEntries()
    for cooldownText, button in pairs(CooldownColor.cooldownTexts) do
        if not cooldownText or cooldownText:IsForbidden() or 
           not button or button:IsForbidden() or
           CooldownColor.hookedButtons[button] ~= cooldownText then
            CooldownColor.cooldownTexts[cooldownText] = nil
        end
    end
    
    for button, cooldownText in pairs(CooldownColor.hookedButtons) do
        if not button or button:IsForbidden() or
           not cooldownText or cooldownText:IsForbidden() or
           CooldownColor.cooldownTexts[cooldownText] ~= button then
            CooldownColor.hookedButtons[button] = nil
        end
    end
end

local function ScheduleColorUpdate(button, delay)
    if not button then return end
    if scheduledUpdates[button] then return end
    scheduledUpdates[button] = true
    
    delay = delay or 0.01
    C_Timer.After(delay, function()
        scheduledUpdates[button] = nil
        if button and not button:IsForbidden() then
            local cooldownText = CooldownColor.hookedButtons[button]
            if cooldownText and not cooldownText:IsForbidden() then
                ApplyCooldownColor(cooldownText, button)
            end
        end
    end)
end

local function HookButtonCooldown(button, forceRecheck)
    if not button or button:IsForbidden() then return end
    
    local existingCooldownText = CooldownColor.hookedButtons[button]
    if existingCooldownText and not forceRecheck then
        if existingCooldownText:IsForbidden() or 
           CooldownColor.cooldownTexts[existingCooldownText] ~= button then
            CooldownColor.hookedButtons[button] = nil
            if existingCooldownText and not existingCooldownText:IsForbidden() then
                CooldownColor.cooldownTexts[existingCooldownText] = nil
            end
        else
            if button.cooldown and button.cooldown:IsShown() then
                local currentText = GetTextSafe(existingCooldownText)
                if not currentText or not CleanText(currentText) then
                    CooldownColor.hookedButtons[button] = nil
                    CooldownColor.cooldownTexts[existingCooldownText] = nil
                else
                    ApplyCooldownColor(existingCooldownText, button)
                    return
                end
            else
                ApplyCooldownColor(existingCooldownText, button)
                return
            end
        end
    elseif existingCooldownText and forceRecheck then
        local currentText = GetTextSafe(existingCooldownText)
        if not currentText or not CleanText(currentText) then
            CooldownColor.hookedButtons[button] = nil
            CooldownColor.cooldownTexts[existingCooldownText] = nil
        end
    end
    
    local cooldownText = FindCooldownText(button)
    
    if not cooldownText or cooldownText:IsForbidden() then
        if button.cooldown and not button.cooldown._cooldownColorRetryHooked then
            button.cooldown:HookScript("OnShow", function()
                C_Timer.After(0.05, function()
                    if button and not button:IsForbidden() then
                        local newCooldownText = FindCooldownText(button)
                        if newCooldownText and not newCooldownText:IsForbidden() then
                            -- Found it now, hook it properly
                            if not CooldownColor.hookedButtons[button] then
                                HookButtonCooldown(button)
                            end
                        end
                    end
                end)
            end)
            button.cooldown._cooldownColorRetryHooked = true
        end
        return
    end
    
    local existingButton = CooldownColor.cooldownTexts[cooldownText]
    if existingButton then
        if existingButton == button then
            return
        else
            if CooldownColor.hookedButtons[existingButton] == cooldownText then
                CooldownColor.hookedButtons[existingButton] = nil
            end
        end
    end
    
    local count = 0
    for _ in pairs(CooldownColor.cooldownTexts) do
        count = count + 1
    end
    if count >= 100 then
        if not button.cooldown or not button.cooldown:IsShown() or button.cooldown:GetAlpha() < 0.3 then
            return
        end
    end
    
    CooldownColor.cooldownTexts[cooldownText] = button
    
    if not cooldownText._cooldownColorHooked then
        hooksecurefunc(cooldownText, "SetText", function(self)
            local button = CooldownColor.cooldownTexts[self]
            if button then 
                lastTextCache[self] = nil
                ApplyCooldownColor(self, button, true)
            end
        end)
        
        hooksecurefunc(cooldownText, "SetTextColor", function(self, r, g, b, a)
            local button = CooldownColor.cooldownTexts[self]
            if button and button.cooldown and button.cooldown:IsShown() then

                if r and g and b and math.abs(r - 1.0) < 0.1 and math.abs(g - 1.0) < 0.1 and math.abs(b - 1.0) < 0.1 then
                    C_Timer.After(0.01, function()
                        if self and not self:IsForbidden() and button and not button:IsForbidden() then
                            local currentText = GetTextSafe(self)
                            if currentText and CleanText(currentText) then
                                lastTextCache[self] = nil
                                ApplyCooldownColor(self, button, true)
                            end
                        end
                    end)
                end
            end
        end)
        
        cooldownText._cooldownColorHooked = true
    end
    
    if button.cooldown and not button.cooldown._cooldownColorHooked then
        button.cooldown:HookScript("OnShow", function()

            C_Timer.After(0.1, function()
                if button and not button:IsForbidden() and button.cooldown and button.cooldown:IsShown() then
                    HookButtonCooldown(button, true)
                    local text = CooldownColor.hookedButtons[button]
                    if text and not text:IsForbidden() then
                        ApplyCooldownColor(text, button, true)
                    end
                end
            end)
        end)
        button.cooldown:HookScript("OnHide", function()
            if cooldownText and not cooldownText:IsForbidden() then
                local text = GetTextSafe(cooldownText)
                local textStr = CleanText(text)
                local seconds = textStr and ParseCooldownTime(textStr)
                if not seconds then
                    SetTextColorSafe(cooldownText, 1.0, 1.0, 1.0)
                    lastColorCache[cooldownText] = "white"
                    lastTextCache[cooldownText] = nil
                end
            end
        end)
        button.cooldown._cooldownColorHooked = true
    end
    
    CooldownColor.hookedButtons[button] = cooldownText
    if button.cooldown and button.cooldown:IsShown() then
        ApplyCooldownColor(cooldownText, button, true)
    end
end

local function HookButtonsByPattern(pattern, count)
    for i = 1, count do
        local button = _G[pattern .. i]
        if button then HookButtonCooldown(button) end
    end
end

local function HookActionButtons()
    HookButtonsByPattern("ActionButton", 96)
    HookButtonsByPattern("MultiBarBottomLeftButton", 12)
    HookButtonsByPattern("MultiBarBottomRightButton", 12)
    HookButtonsByPattern("MultiBarRightButton", 12)
    HookButtonsByPattern("MultiBarLeftButton", 12)
    HookButtonsByPattern("PetActionButton", 10)
    HookButtonsByPattern("StanceButton", 10)
end

local function HookActionButtonSystem()
    if ActionButton_UpdateCooldown then
        hooksecurefunc("ActionButton_UpdateCooldown", function(button)
            if button then
                HookButtonCooldown(button, true)

                local text = CooldownColor.hookedButtons[button]
                if text and not text:IsForbidden() then
                    ApplyCooldownColor(text, button, true)
                end
            end
        end)
    end
    
    if ActionButton_Update then
        hooksecurefunc("ActionButton_Update", function(button)
            if button then 
                HookButtonCooldown(button, true) 
            end
        end)
    end
    
    if CooldownFrame_SetTimer then
        hooksecurefunc("CooldownFrame_SetTimer", function(cooldownFrame, start, duration)
            if cooldownFrame and cooldownFrame:GetParent() then
                local button = cooldownFrame:GetParent()
                HookButtonCooldown(button, true)

                local text = CooldownColor.hookedButtons[button]
                if text and not text:IsForbidden() then
                    ApplyCooldownColor(text, button, true)
                end
            end
        end)
    end
end

local scannerFrame = nil
local scannerStarted = false
local scannerHealthCheck = nil

local function StartButtonScanner()
    if scannerStarted and scannerFrame and scannerFrame:GetScript("OnUpdate") then return end
    
    scannerFrame = CreateFrame("Frame")
    local scanCount, updateCount, cleanupCount, recheckCount = 0, 0, 0, 0
    local sampleCounter = 0
    scannerStarted = true

    scannerFrame:SetScript("OnUpdate", function(self, elapsed)
        scanCount = scanCount + elapsed
        updateCount = updateCount + elapsed
        cleanupCount = cleanupCount + elapsed
        recheckCount = recheckCount + elapsed
        

        if cleanupCount >= 15.0 then
            cleanupCount = 0
            CleanupInvalidEntries()
            for button in pairs(scheduledUpdates) do
                if not button or button:IsForbidden() then
                    scheduledUpdates[button] = nil
                end
            end
            for cooldownText in pairs(lastColorCache) do
                if not cooldownText or cooldownText:IsForbidden() or 
                   not CooldownColor.cooldownTexts[cooldownText] then
                    lastColorCache[cooldownText] = nil
                    lastTextCache[cooldownText] = nil
                end
            end
        end
        

        if scanCount >= 15.0 then
            scanCount = 0
            HookButtonsByPattern("ActionButton", 96)
            HookButtonsByPattern("MultiBarBottomLeftButton", 12)
            HookButtonsByPattern("MultiBarBottomRightButton", 12)
            HookButtonsByPattern("MultiBarRightButton", 12)
            HookButtonsByPattern("MultiBarLeftButton", 12)
            HookButtonsByPattern("PetActionButton", 10)
            HookButtonsByPattern("StanceButton", 10)
        end
        

        if updateCount >= 0.3 then
            updateCount = 0
            
            local count = 0
            local maxEntries = 80
            local forceReapplyCount = 0
            for cooldownText, button in pairs(CooldownColor.cooldownTexts) do
                if count >= maxEntries then break end
                if cooldownText and not cooldownText:IsForbidden() and
                   button and not button:IsForbidden() and
                   button.cooldown and button.cooldown:IsShown() and
                   button.cooldown:GetAlpha() > 0.3 then
                    count = count + 1

                    if forceReapplyCount % 10 == 0 then
                        ApplyCooldownColor(cooldownText, button, true)
                    else
                        ApplyCooldownColor(cooldownText, button, false)
                    end
                    forceReapplyCount = forceReapplyCount + 1
                elseif cooldownText and not cooldownText:IsForbidden() and
                       button and not button:IsForbidden() then
                else
                    CooldownColor.cooldownTexts[cooldownText] = nil
                end
            end
        end
        

        if recheckCount >= 1.0 then
            recheckCount = 0
            
            sampleCounter = sampleCounter + 1
            local sampleOffset = (sampleCounter * 8) % 96 
            for i = 1, 8 do
                local idx = ((sampleOffset + i - 1) % 96) + 1
                local button = _G["ActionButton" .. idx]
                if button and not button:IsForbidden() and
                   button.cooldown and button.cooldown:IsShown() and
                   button.cooldown:GetAlpha() > 0.3 then
                    if not CooldownColor.hookedButtons[button] then
                        HookButtonCooldown(button, true)
                    end
                end
            end
        end
    end)
    
    if scannerHealthCheck then
        scannerHealthCheck:Cancel()
    end
    scannerHealthCheck = C_Timer.NewTicker(10.0, function()
        if not scannerFrame or not scannerFrame:GetScript("OnUpdate") then
            scannerStarted = false
            StartButtonScanner()
        end
    end)
    

    local colorReapplyTicker = C_Timer.NewTicker(2.0, function()
        local reapplied = 0
        for cooldownText, button in pairs(CooldownColor.cooldownTexts) do
            if reapplied >= 20 then break end
            if cooldownText and not cooldownText:IsForbidden() and
               button and not button:IsForbidden() and
               button.cooldown and button.cooldown:IsShown() and
               button.cooldown:GetAlpha() > 0.3 then
                local text = GetTextSafe(cooldownText)
                if text and CleanText(text) then

                    lastTextCache[cooldownText] = nil
                    ApplyCooldownColor(cooldownText, button, true)
                    reapplied = reapplied + 1
                end
            end
        end
    end)
    
    scannerFrame._colorReapplyTicker = colorReapplyTicker
end

local initAttempts = 0
local maxInitAttempts = 20
local initFrame = nil

local function TryHook()
    HookActionButtons()
    HookActionButtonSystem()
end

local function EnsureScannerStarted()
    if not scannerStarted then
        StartButtonScanner()
    end
end

local function AttemptInitialization(attemptNumber)
    initAttempts = initAttempts + 1
    
    -- Try to hook buttons
    local buttonsFound = false
    for i = 1, 12 do
        local button = _G["ActionButton" .. i]
        if button and button.cooldown then
            buttonsFound = true
            break
        end
    end
    
    if buttonsFound or attemptNumber >= 3 then
        TryHook()
        EnsureScannerStarted()
        
        local verified = false
        if ActionButton_UpdateCooldown or ActionButton_Update or CooldownFrame_SetTimer then
            verified = true
        end
        
        if verified or attemptNumber >= 5 then

            return true
        end
    end
    
    if initAttempts < maxInitAttempts then
        local delay = math.min(0.5 + (attemptNumber * 0.2), 2.0)
        C_Timer.After(delay, function()
            AttemptInitialization(attemptNumber + 1)
        end)
    else

        EnsureScannerStarted()
    end
    
    return false
end

local function Initialize()
    if CooldownColor.isInitialized then return end
    
    initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("ADDON_LOADED")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    initFrame:RegisterEvent("UPDATE_BINDINGS")
    
    local function OnEvent(self, event, addonName)
        if event == "ADDON_LOADED" and addonName == "Blizzard_ActionBar" then
            C_Timer.After(0.3, function()
                AttemptInitialization(1)
            end)
        elseif event == "PLAYER_LOGIN" then
            C_Timer.After(0.5, function()
                AttemptInitialization(1)
            end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.8, function()
                AttemptInitialization(1)
            end)
        elseif event == "UPDATE_BINDINGS" then

            C_Timer.After(0.2, function()
                if initAttempts < 3 then
                    AttemptInitialization(1)
                end
            end)
        end
    end
    
    initFrame:SetScript("OnEvent", OnEvent)
    
    C_Timer.After(0.1, function()
        AttemptInitialization(1)
    end)
    
    C_Timer.After(1.0, function()
        if not scannerStarted then
            AttemptInitialization(2)
        end
    end)
    
    C_Timer.After(2.5, function()
        if not scannerStarted then
            AttemptInitialization(3)
        end
    end)
    
    C_Timer.After(5.0, function()
        
        EnsureScannerStarted()
        TryHook()
    end)
    
    CooldownColor.isInitialized = true
end

Initialize()
