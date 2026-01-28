-- ========================================
-- COOLDOWN COLOR MODULE
-- ========================================
local CooldownColor = {}
CooldownColor.isInitialized = false
CooldownColor.activeCooldowns = {}

local updateTicker = nil

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

local function GetDuration(cooldown)
    local actionID = GetActionID(cooldown)
    if not actionID then return nil end
    
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
    local parent = cooldown:GetParent()
    if not parent or not parent.action then return false end
    
    local parentName = parent:GetName()
    if not parentName then return false end
    
    local patterns = {
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
    
    for _, pattern in ipairs(patterns) do
        if parentName:match(pattern) then
            return true
        end
    end
    
    return false
end

local function UpdateCooldownColor(cooldownFrame, cdInfo)
    if not cooldownFrame or cooldownFrame:IsForbidden() or not cooldownFrame:IsShown() then
        return
    end
    
    if not IsActionButtonCooldown(cooldownFrame) then
        return
    end
    
    local text = cooldownFrame:GetCountdownFontString()
    if not text or text:IsForbidden() then
        return
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

local function StartUpdateTicker()
    if updateTicker then return end
    
    updateTicker = C_Timer.NewTicker(0.1, function()
        for cooldown, cdInfo in pairs(CooldownColor.activeCooldowns) do
            if cooldown and not cooldown:IsForbidden() and cooldown:IsShown() then
                UpdateCooldownColor(cooldown, cdInfo)
            else
                CooldownColor.activeCooldowns[cooldown] = nil
            end
        end
        
        if not next(CooldownColor.activeCooldowns) then
            StopUpdateTicker()
        end
    end)
end

local function StopUpdateTicker()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
end

local function InitCooldown(cooldown, durationObject)
    if not cooldown or cooldown:IsForbidden() then return end
    
    if not IsActionButtonCooldown(cooldown) then return end
    
    if not durationObject then
        durationObject = GetDuration(cooldown)
    end
    
    CooldownColor.activeCooldowns[cooldown] = {
        duration = durationObject,
        cooldown = cooldown
    }
    
    if not cooldown._cooldownColorHooked then
        cooldown:HookScript("OnShow", function(self)
            if self and not self:IsForbidden() then
                local cdInfo = CooldownColor.activeCooldowns[self]
                if not cdInfo then
                    InitCooldown(self, GetDuration(self))
                else
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
    for i = 1, select('#', ...) do
        local value = select(i, ...)
        if issecretvalue(value) then
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
        
        local durationObject
        if notSecret(start, duration, modRate) then
            durationObject = C_DurationUtil.CreateDuration()
            durationObject:SetTimeFromStart(start, duration, modRate)
        else
            durationObject = GetDuration(cooldown)
        end
        
        InitCooldown(cooldown, durationObject)
    end)
    
    hooksecurefunc(cooldown_mt, 'SetCooldownDuration', function(cooldown, duration, modRate)
        if cooldown:IsForbidden() then return end
        
        local durationObject
        if notSecret(duration, modRate) then
            durationObject = C_DurationUtil.CreateDuration()
            durationObject:SetTimeFromStart(GetTime(), duration, modRate)
        else
            durationObject = GetDuration(cooldown)
        end
        
        InitCooldown(cooldown, durationObject)
    end)
    
    hooksecurefunc(cooldown_mt, 'SetCooldownFromDurationObject', function(cooldown, durationObject)
        if cooldown:IsForbidden() then return end
        InitCooldown(cooldown, durationObject)
    end)
    
    hooksecurefunc(cooldown_mt, 'SetCooldownFromExpirationTime', function(cooldown, expirationTime, duration, modRate)
        if cooldown:IsForbidden() then return end
        
        local durationObject
        if notSecret(expirationTime, duration, modRate) then
            durationObject = C_DurationUtil.CreateDuration()
            durationObject:SetTimeFromEnd(expirationTime, duration, modRate)
        else
            durationObject = GetDuration(cooldown)
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
