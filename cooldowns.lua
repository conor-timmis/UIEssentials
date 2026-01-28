-- ========================================
-- COOLDOWN COLOR MODULE
-- ========================================
local CooldownColor = {}
CooldownColor.isInitialized = false
CooldownColor.activeCooldowns = {}

local updateTicker = nil

local BUTTON_PATTERNS = {
    "^ActionButton%d+",
    "^MultiBarBottomLeftButton%d+",
    "^MultiBarBottomRightButton%d+",
    "^MultiBarRightButton%d+",
    "^MultiBarLeftButton%d+",
    "^MultiBar5Button%d+",
    "^MultiBar6Button%d+",
    "^MultiBar7Button%d+",
    "^PetActionButton%d+",
    "^StanceButton%d+"
}

local function CreateColorCurve()
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    
    curve:AddPoint(0, CreateColor(0.0, 1.0, 0.0, 1.0))
    curve:AddPoint(8.5, CreateColor(1.0, 0.85, 0.0, 1.0))
    curve:AddPoint(30.5, CreateColor(1.0, 0.0, 0.0, 1.0))
    
    return curve
end

local colorCurve = CreateColorCurve()

local function GetActionID(cooldown)
    local parent = cooldown:GetParent()
    if parent then
        return parent.action or parent:GetAttribute("action")
    end
    return nil
end

local function GetDuration(cooldown, actionID)
    if not actionID then
        actionID = GetActionID(cooldown)
        if not actionID then return nil end
    end
    
    local key = cooldown:GetParentKey()
    
    if key == "chargeCooldown" then
        return C_ActionBar.GetActionChargeDuration(actionID)
    elseif key == "lossOfControlCooldown" then
        return C_ActionBar.GetActionLossOfControlCooldownDuration(actionID)
    else
        return C_ActionBar.GetActionCooldownDuration(actionID)
    end
end

local function IsActionButtonCooldown(cooldown)
    if cooldown._isActionButtonCooldown ~= nil then
        return cooldown._isActionButtonCooldown
    end
    
    local parent = cooldown:GetParent()
    if not parent or not parent.action then
        cooldown._isActionButtonCooldown = false
        return false
    end
    
    local parentName = parent:GetName()
    if not parentName then
        cooldown._isActionButtonCooldown = false
        return false
    end
    
    for i = 1, #BUTTON_PATTERNS do
        if parentName:match(BUTTON_PATTERNS[i]) then
            cooldown._isActionButtonCooldown = true
            return true
        end
    end
    
    cooldown._isActionButtonCooldown = false
    return false
end

local function UpdateCooldownColor(cooldownFrame, cdInfo)
    if not cooldownFrame or cooldownFrame:IsForbidden() then
        return
    end
    
    if not cooldownFrame:IsShown() then
        return
    end
    
    local text = cdInfo.text
    if not text or text:IsForbidden() then
        text = cooldownFrame:GetCountdownFontString()
        if not text or text:IsForbidden() then
            return
        end
        cdInfo.text = text
    end
    
    local r, g, b, a = 1, 1, 1, 1
    
    if cdInfo.duration then
        local success, colorObj = pcall(function()
            return cdInfo.duration:EvaluateRemainingDuration(colorCurve)
        end)
        
        if success and colorObj then
            local success2, r2, g2, b2, a2 = pcall(function()
                return colorObj:GetRGBA()
            end)
            
            if success2 and r2 and g2 and b2 then
                r, g, b, a = r2, g2, b2, (a2 or 1.0)
            end
        end
    end
    
    text:SetTextColor(r, g, b, a)
end

local function StopUpdateTicker()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
end

local function StartUpdateTicker()
    if updateTicker then return end
    
    updateTicker = C_Timer.NewTicker(0.1, function()
        local toRemove = {}
        local count = 0
        
        for cooldown, cdInfo in pairs(CooldownColor.activeCooldowns) do
            count = count + 1
            if cooldown and not cooldown:IsForbidden() and cooldown:IsShown() then
                UpdateCooldownColor(cooldown, cdInfo)
            else
                toRemove[cooldown] = true
            end
        end
        
        for cooldown in pairs(toRemove) do
            CooldownColor.activeCooldowns[cooldown] = nil
            count = count - 1
        end
        
        if count == 0 then
            StopUpdateTicker()
        end
    end)
end

local function InitCooldown(cooldown, durationObject)
    if not cooldown or cooldown:IsForbidden() then return end
    
    if not IsActionButtonCooldown(cooldown) then return end
    
    local actionID = GetActionID(cooldown)
    if not durationObject then
        durationObject = GetDuration(cooldown, actionID)
    end
    
    local text = cooldown:GetCountdownFontString()
    
    CooldownColor.activeCooldowns[cooldown] = {
        duration = durationObject,
        cooldown = cooldown,
        actionID = actionID,
        text = text
    }
    
    if not cooldown._cooldownColorHooked then
        cooldown:HookScript("OnShow", function(self)
            if self and not self:IsForbidden() then
                local cdInfo = CooldownColor.activeCooldowns[self]
                if not cdInfo then
                    InitCooldown(self, GetDuration(self))
                else
                    if not cdInfo.text or cdInfo.text:IsForbidden() then
                        cdInfo.text = self:GetCountdownFontString()
                    end
                    UpdateCooldownColor(self, cdInfo)
                end
                
                if not updateTicker then
                    StartUpdateTicker()
                end
            end
        end)
        
        cooldown:HookScript("OnHide", function(self)
            if self then
                CooldownColor.activeCooldowns[self] = nil
                if not next(CooldownColor.activeCooldowns) then
                    StopUpdateTicker()
                end
            end
        end)
        
        cooldown._cooldownColorHooked = true
    end
    
    UpdateCooldownColor(cooldown, CooldownColor.activeCooldowns[cooldown])
    
    if durationObject and not updateTicker then
        StartUpdateTicker()
    end
end

local function StopCooldown(cooldown)
    if cooldown then
        CooldownColor.activeCooldowns[cooldown] = nil
        if not next(CooldownColor.activeCooldowns) then
            StopUpdateTicker()
        end
    end
end

local function notSecret(...)
    local count = select('#', ...)
    for i = 1, count do
        if issecretvalue(select(i, ...)) then
            return false
        end
    end
    return true
end

local function HookCooldownMetatable()
    if not ActionButton1Cooldown then
        return false
    end
    
    local cooldown_mt = getmetatable(ActionButton1Cooldown)
    if not cooldown_mt or not cooldown_mt.__index then
        return false
    end
    
    cooldown_mt = cooldown_mt.__index
    
    if cooldown_mt._cooldownColorHooked then
        return true
    end
    
    hooksecurefunc(cooldown_mt, 'SetCooldown', function(cooldown, start, duration, modRate)
        if cooldown:IsForbidden() then return end
        
        local cdInfo = CooldownColor.activeCooldowns[cooldown]
        local actionID = cdInfo and cdInfo.actionID or GetActionID(cooldown)
        
        local durationObject
        if notSecret(start, duration, modRate) then
            durationObject = C_DurationUtil.CreateDuration()
            durationObject:SetTimeFromStart(start, duration, modRate)
        else
            durationObject = GetDuration(cooldown, actionID)
        end
        
        InitCooldown(cooldown, durationObject)
    end)
    
    hooksecurefunc(cooldown_mt, 'SetCooldownDuration', function(cooldown, duration, modRate)
        if cooldown:IsForbidden() then return end
        
        local cdInfo = CooldownColor.activeCooldowns[cooldown]
        local actionID = cdInfo and cdInfo.actionID or GetActionID(cooldown)
        
        local durationObject
        if notSecret(duration, modRate) then
            durationObject = C_DurationUtil.CreateDuration()
            durationObject:SetTimeFromStart(GetTime(), duration, modRate)
        else
            durationObject = GetDuration(cooldown, actionID)
        end
        
        InitCooldown(cooldown, durationObject)
    end)
    
    hooksecurefunc(cooldown_mt, 'SetCooldownFromDurationObject', function(cooldown, durationObject)
        if cooldown:IsForbidden() then return end
        InitCooldown(cooldown, durationObject)
    end)
    
    hooksecurefunc(cooldown_mt, 'SetCooldownFromExpirationTime', function(cooldown, expirationTime, duration, modRate)
        if cooldown:IsForbidden() then return end
        
        local cdInfo = CooldownColor.activeCooldowns[cooldown]
        local actionID = cdInfo and cdInfo.actionID or GetActionID(cooldown)
        
        local durationObject
        if notSecret(expirationTime, duration, modRate) then
            durationObject = C_DurationUtil.CreateDuration()
            durationObject:SetTimeFromEnd(expirationTime, duration, modRate)
        else
            durationObject = GetDuration(cooldown, actionID)
        end
        
        InitCooldown(cooldown, durationObject)
    end)
    
    hooksecurefunc(cooldown_mt, 'Clear', function(cooldown)
        StopCooldown(cooldown)
    end)
    
    cooldown_mt._cooldownColorHooked = true
    return true
end

local function Initialize()
    if CooldownColor.isInitialized then return end
    
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("ADDON_LOADED")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    initFrame:SetScript("OnEvent", function(self, event, addonName)
        if event == "ADDON_LOADED" and addonName == "Blizzard_ActionBar" then
            C_Timer.After(0.3, HookCooldownMetatable)
        elseif event == "PLAYER_LOGIN" then
            C_Timer.After(0.5, HookCooldownMetatable)
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.8, HookCooldownMetatable)
        end
    end)
    
    C_Timer.After(0.1, function()
        if not HookCooldownMetatable() then
            C_Timer.After(1.0, HookCooldownMetatable)
        end
    end)
    
    CooldownColor.isInitialized = true
end

Initialize()
