-- UIEssentials - Options/UI
local addonName, addon = ...

local SettingsManager = addon.SettingsManager
local CursorHighlight = addon.CursorHighlight
local CutsceneSkipper = addon.CutsceneSkipper
local AutoCompareDisabler = addon.AutoCompareDisabler

local OptionsPanel = addon.OptionsPanel or {}
addon.OptionsPanel = OptionsPanel
OptionsPanel.frame = OptionsPanel.frame or nil

local PANEL_WIDTH = 520
local PANEL_HEIGHT = 380
local COLUMN_WIDTH = 240
local COLUMN_SPACING = 20
local MODERN_BG = {0.12, 0.12, 0.14, 0.98}
local MODERN_BORDER = {0.25, 0.25, 0.28, 1.0}

local COLOR_TITLE = {0.95, 0.95, 0.95, 1.0}
local COLOR_VERSION = {0.7, 0.7, 0.7, 1.0}
local COLOR_HEADER = {0.85, 0.85, 0.85, 1.0}
local COLOR_LABEL = {0.9, 0.9, 0.9, 1.0}
local COLOR_HINT = {0.65, 0.65, 0.65, 1.0}

local function CreateCheckbox(parent, label, tooltip, x, y, getFunc, setFunc)
    local check = CreateFrame("Button", nil, parent)
    check:SetPoint("TOPLEFT", x, y)
    check:SetSize(20, 20)

    local function hideTex(t)
        if t then
            t:SetTexture(nil)
            t:SetAlpha(0)
            t:ClearAllPoints()
            t:SetSize(0.001, 0.001)
            t:Hide()
        end
    end
    hideTex(check:GetNormalTexture())
    hideTex(check:GetPushedTexture())
    hideTex(check:GetHighlightTexture())
    hideTex(check:GetDisabledTexture())

    local bg = check:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
    check.bg = bg

    local border = check:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.4, 0.4, 0.4, 1.0)
    check.border = border

    local checkmark = check:CreateTexture(nil, "OVERLAY")
    checkmark:SetPoint("CENTER")
    checkmark:SetSize(16, 16)
    checkmark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkmark:SetVertexColor(0.2, 0.8, 0.2, 1.0)
    checkmark:Hide()
    check.checkmark = checkmark

    check:SetScript("OnClick", function(self)
        local checked = not (getFunc and getFunc())
        if setFunc then setFunc(checked) end
        if checked then
            self.bg:SetColorTexture(0.15, 0.3, 0.15, 1.0)
            self.border:SetColorTexture(0.3, 0.6, 0.3, 1.0)
            self.checkmark:Show()
        else
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
            self.border:SetColorTexture(0.4, 0.4, 0.4, 1.0)
            self.checkmark:Hide()
        end
    end)

    check:SetScript("OnEnter", function(self)
        local checked = getFunc and getFunc()
        if not checked then
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
        local checked = getFunc and getFunc()
        if not checked then
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

    radio.isSelected = (value == currentValue)
    local parentWidth = (parent and parent.GetWidth and parent:GetWidth()) or 200
    radio:SetSize(math.max(120, parentWidth - x - 8), 20)

    local rowBg = radio:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(0, 0, 0, 0)

    local indicatorBg = radio:CreateTexture(nil, "BORDER")
    indicatorBg:SetPoint("LEFT", 0, 0)
    indicatorBg:SetSize(16, 16)

    local indicatorBorder = radio:CreateTexture(nil, "ARTWORK")
    indicatorBorder:SetAllPoints(indicatorBg)

    local indicatorMark = radio:CreateTexture(nil, "OVERLAY")
    indicatorMark:SetPoint("CENTER", indicatorBg, "CENTER")
    indicatorMark:SetSize(14, 14)
    indicatorMark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    indicatorMark:SetVertexColor(0.2, 0.8, 0.2, 1.0)
    indicatorMark:Hide()

    local labelText = radio:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("LEFT", indicatorBg, "RIGHT", 8, 0)
    labelText:SetPoint("RIGHT", -6, 0)
    labelText:SetJustifyH("LEFT")
    labelText:SetText(label)
    radio.labelText = labelText

    local function ApplySelected(selected)
        if selected then
            rowBg:SetColorTexture(0.12, 0.22, 0.12, 0.35)
            indicatorBg:SetColorTexture(0.15, 0.3, 0.15, 1.0)
            indicatorBorder:SetColorTexture(0.3, 0.6, 0.3, 1.0)
            indicatorMark:Show()
            labelText:SetTextColor(0.3, 0.9, 0.3, 1.0)
        else
            rowBg:SetColorTexture(0, 0, 0, 0)
            indicatorBg:SetColorTexture(0.2, 0.2, 0.2, 1.0)
            indicatorBorder:SetColorTexture(0.4, 0.4, 0.4, 1.0)
            indicatorMark:Hide()
            labelText:SetTextColor(unpack(COLOR_LABEL))
        end
    end

    local function UpdateVisualState()
        ApplySelected(radio.isSelected)
    end

    radio:SetScript("OnClick", function(self)
        if setFunc then setFunc(value) end
    end)

    radio:SetScript("OnEnter", function(self)
        if not radio.isSelected then
            rowBg:SetColorTexture(1, 1, 1, 0.04)
            indicatorBg:SetColorTexture(0.25, 0.25, 0.25, 1.0)
            indicatorBorder:SetColorTexture(0.5, 0.5, 0.5, 1.0)
            labelText:SetTextColor(0.85, 0.85, 0.85, 1.0)
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

    radio.UpdateState = function(self, newCurrentValue)
        self.isSelected = (value == newCurrentValue)
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

    local textObj = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    textObj:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    textObj:SetPoint("RIGHT", dropdown, "RIGHT", -24, 0)
    textObj:SetJustifyH("LEFT")
    textObj:SetTextColor(unpack(COLOR_LABEL))
    dropdown.text = textObj

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

    local function CreateMenuItem(v, t, yPos)
        local item = CreateFrame("Button", nil, menuFrame)
        item:SetSize(150, 22)
        item:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 0, -yPos)

        local itemBg = item:CreateTexture(nil, "BACKGROUND")
        itemBg:SetAllPoints()
        itemBg:SetColorTexture(0.2, 0.2, 0.2, 0)
        item.bg = itemBg

        local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemText:SetPoint("LEFT", item, "LEFT", 8, 0)
        itemText:SetText(t)
        itemText:SetTextColor(unpack(COLOR_LABEL))

        item:SetScript("OnEnter", function(self) itemBg:SetColorTexture(0.3, 0.3, 0.3, 1.0) end)
        item:SetScript("OnLeave", function(self) itemBg:SetColorTexture(0.2, 0.2, 0.2, 0) end)
        item:SetScript("OnClick", function()
            EnsureCloseFrameHidden()
            menuFrame:Hide()
            UpdateText()
            if setFunc then
                C_Timer.After(0.1, function()
                    if setFunc then setFunc(v) end
                end)
            end
        end)

        return item
    end

    local function CloseMenuOnClickOutside()
        if not menuFrame:IsShown() then return end

        local xPos, yPos = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        xPos, yPos = xPos / scale, yPos / scale

        local mx, my = menuFrame:GetLeft(), menuFrame:GetTop()
        local mw, mh = menuFrame:GetWidth(), menuFrame:GetHeight()
        local inMenu = (xPos >= mx and xPos <= mx + mw and yPos <= my and yPos >= my - mh)

        local dx, dy = dropdown:GetLeft(), dropdown:GetTop()
        local dw, dh = dropdown:GetWidth(), dropdown:GetHeight()
        local inDropdown = (xPos >= dx and xPos <= dx + dw and yPos <= dy and yPos >= dy - dh)

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

        for v, t in pairs(options) do
            local item = CreateMenuItem(v, t, yPos)
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
    version:SetText("Version 2.5")
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
    closeBtn:SetScript("OnEnter", function(self) closeBg:SetColorTexture(0.4, 0.15, 0.15, 1.0) end)
    closeBtn:SetScript("OnLeave", function(self) closeBg:SetColorTexture(0.2, 0.2, 0.2, 1.0) end)
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
            if radio.UpdateState then radio:UpdateState(currentValue) end
        end
    end

    local radio1 = CreateRadioButton(leftColumn, "Green Square",
        "Display a green square at your cursor", 24, yOffset - 73,
        "square", SettingsManager:Get("cursorStyle") or "square",
        function(val)
            SettingsManager:Set("cursorStyle", val)
            UpdateCursorStyleRadios()
            if SettingsManager:Get("showCursorHighlight") then CursorHighlight.StartTracking() end
        end)
    table.insert(cursorStyleRadios, radio1)

    local radio2 = CreateRadioButton(leftColumn, "Star Surge",
        "Display a Star Surge trail at your cursor", 24, yOffset - 93,
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
            local cc = addon.CooldownColor
            if cc then
                if val then cc.Initialize() else cc.Disable() end
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

    local reloadBtnText = reloadBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reloadBtnText:SetPoint("CENTER")
    reloadBtnText:SetText("Reload UI")
    reloadBtnText:SetTextColor(0.95, 0.95, 0.95, 1.0)

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

    local reloadHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reloadHint:SetPoint("BOTTOM", reloadBtn, "TOP", 0, 4)
    reloadHint:SetText("Please /reload to apply ANY changes")
    reloadHint:SetTextColor(unpack(COLOR_HINT))

    frame.checkboxes = {
        enableTooltips = enableTooltips,
        itemLevelDecimals = itemLevelDecimals,
        cursorHighlight = cursorHighlight,
        cooldownColors = cooldownColors,
        hideRealmRaid = hideRealmRaid,
        hideRealmParty = hideRealmParty,
        autoSkipCutscenes = autoSkipCutscenes,
        disableAutoCompare = disableAutoCompare
    }
    frame.UpdateCursorStyleRadios = UpdateCursorStyleRadios
    frame.UpdateCheckboxes = function()
        for _, checkbox in pairs(frame.checkboxes) do
            if checkbox.UpdateState then checkbox:UpdateState() end
        end
        if frame.UpdateCursorStyleRadios then frame.UpdateCursorStyleRadios() end
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

SlashCmdList.UIESSENTIALS = OptionsPanel.Show
SLASH_UIESSENTIALS1, SLASH_UIESSENTIALS2 = "/ue", "/uiessentials"

