--[[
设置界面：/qct 打开。所有改动即时生效（提示框正开着的话会立即重建面板）。
用自己画的控件（不用 OptionsSliderTemplate 之类），避免不同客户端版本模板缺失。
]]

local ADDON, ns = ...
local QCT = ns

local O = {}
QCT.Options = O

local PANEL_NAME = "QuestChainTipOptions"
local WIDTH = 430
local ROW = 30

local panel
local controls = {}

-- 暴露给测试用，也方便 SyncControls 统一遍历
O.controls = controls

--------------------------------------------------------------------------------
-- 生效
--------------------------------------------------------------------------------

local function Apply()
    if QCT.Tooltip and QCT.Tooltip.Refresh and GameTooltip and GameTooltip:IsShown() then
        pcall(QCT.Tooltip.Refresh, QCT.Tooltip, true)
    end
end

--------------------------------------------------------------------------------
-- 控件
--------------------------------------------------------------------------------

local function NewLabel(parent, text, x, y, fontObject)
    local fs = parent:CreateFontString(nil, "ARTWORK")
    fs:SetFontObject(fontObject or GameFontHighlight)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function NewCheck(parent, label, key, x, y)
    local check = CreateFrame("Button", nil, parent)
    check:SetSize(20, 20)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local background = check:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetVertexColor(0.10, 0.10, 0.10, 1)
    background:SetAllPoints()

    local border = check:CreateTexture(nil, "BORDER")
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0.35, 0.35, 0.35, 1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetDrawLayer("BORDER", -1)

    local mark = check:CreateTexture(nil, "ARTWORK")
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    mark:SetPoint("TOPLEFT", 1, -1)
    mark:SetPoint("BOTTOMRIGHT", -1, 1)
    mark:SetVertexColor(1, 0.82, 0)

    local text = parent:CreateFontString(nil, "ARTWORK")
    text:SetFontObject(GameFontHighlight)
    text:SetPoint("LEFT", check, "RIGHT", 8, 0)
    text:SetText(label)
    text:SetTextColor(1, 0.82, 0)

    check:SetScript("OnEnter", function() text:SetTextColor(1, 1, 1) end)
    check:SetScript("OnLeave", function() text:SetTextColor(1, 0.82, 0) end)
    check:SetScript("OnClick", function()
        QCT.db[key] = not QCT.db[key]
        mark:SetShown(QCT.db[key] and true or false)
        Apply()
    end)

    check.mark = mark
    check.label = text
    check.key = key
    check.kind = "check"
    controls[#controls + 1] = check
    return check
end

local function NewStepper(parent, label, key, minValue, maxValue, labelX, y, buttonX)
    NewLabel(parent, label, labelX, y + 3)

    local minus = CreateFrame("Button", nil, parent)
    minus:SetSize(22, 22)
    minus:SetPoint("TOPLEFT", parent, "TOPLEFT", buttonX or 310, y)
    minus:SetNormalFontObject(GameFontNormal)
    minus:SetText("−")

    local value = parent:CreateFontString(nil, "ARTWORK")
    value:SetFontObject(GameFontHighlight)
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    value:SetWidth(30)
    value:SetJustifyH("CENTER")

    local plus = CreateFrame("Button", nil, parent)
    plus:SetSize(22, 22)
    plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
    plus:SetNormalFontObject(GameFontNormal)
    plus:SetText("+")

    local function update()
        value:SetText(tostring(QCT.db[key] or minValue))
    end

    minus:SetScript("OnClick", function()
        local current = tonumber(QCT.db[key]) or minValue
        QCT.db[key] = math.max(minValue, current - 1)
        update()
        Apply()
    end)
    plus:SetScript("OnClick", function()
        local current = tonumber(QCT.db[key]) or minValue
        QCT.db[key] = math.min(maxValue, current + 1)
        update()
        Apply()
    end)

    update()

    local widget = { kind = "stepper", key = key, update = update, minValue = minValue, minus = minus, plus = plus }
    controls[#controls + 1] = widget
    return widget
end

local function NewButton(parent, text, width, x, y, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

--------------------------------------------------------------------------------
-- 同步控件显示
--------------------------------------------------------------------------------

local function SyncControls()
    for _, control in ipairs(controls) do
        if control.kind == "check" then
            if control.mark then
                control.mark:SetShown(QCT.db[control.key] and true or false)
            end
        elseif control.kind == "stepper" and control.update then
            control.update()
        elseif control.kind == "mode" and control.update then
            control.update()
        end
    end
end

--------------------------------------------------------------------------------
-- 创建面板
--------------------------------------------------------------------------------

local function CreatePanel()
    local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Frame", PANEL_NAME, UIParent, backdropTemplate)
    frame:SetSize(WIDTH, 450)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.95)
    else
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
        background:SetAllPoints()
    end

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("任务链提示 - 设置")

    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("在世界地图上悬停任务图标显示简介，按住 Shift 打开整条任务链详情窗；小地图上不弹")
    subtitle:SetTextColor(0.7, 0.7, 0.7)

    if UIPanelCloseButton then
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
    end

    local y = -60

    NewCheck(frame, "启用插件", "enabled", 22, y)
    y = y - ROW

    -- 悬停面板显示范围：三态循环按钮
    NewLabel(frame, "悬停面板", 22, y + 3)
    local MODE_ORDER = { "off", "map", "all" }
    local MODE_LABEL = { off = "关闭", map = "仅世界地图", all = "全部位置" }
    local modeButton
    modeButton = NewButton(frame, MODE_LABEL[QCT.db.panelMode or "map"], 120, 200, y, function()
        local current = QCT.db.panelMode or "map"
        local index = 1
        for i, value in ipairs(MODE_ORDER) do
            if value == current then index = i end
        end
        QCT.db.panelMode = MODE_ORDER[index % #MODE_ORDER + 1]
        modeButton:SetText(MODE_LABEL[QCT.db.panelMode])
        Apply()
    end)
    controls[#controls + 1] = {
        kind = "mode",
        update = function() modeButton:SetText(MODE_LABEL[QCT.db.panelMode or "map"]) end,
    }
    y = y - ROW

    NewCheck(frame, "显示任务描述", "showDescription", 22, y)
    NewStepper(frame, "描述最多行数", "descLines", 1, 12, 200, y + 3)
    y = y - ROW

    NewCheck(frame, "显示任务奖励（经验/金钱/物品/声望）", "showRewards", 22, y)
    y = y - ROW

    NewCheck(frame, "显示后续任务链", "showChain", 22, y)
    y = y - ROW

    NewCheck(frame, "后续任务每行显示奖励与状态", "chainRewards", 40, y)
    y = y - ROW

    NewStepper(frame, "普通状态显示层数", "chainDepth", 1, 10, 40, y + 3)
    y = y - ROW

    NewStepper(frame, "详情窗最多显示环数", "chainDepthShift", 1, 40, 40, y + 3)
    y = y - ROW

    NewCheck(frame, "显示前置任务", "showPrereq", 22, y)
    y = y - ROW

    NewCheck(frame, "聊天框显示诊断信息（排查问题时用）", "diag", 22, y)
    y = y - ROW

    NewCheck(frame, "调试输出（排查问题时用）", "debug", 22, y)
    y = y - ROW - 8

    O.resetButton = NewButton(frame, "恢复默认", 100, 22, y, function()
        for key, value in pairs(QCT.Defaults or {}) do
            QCT.db[key] = value
        end
        SyncControls()
        Apply()
        QCT:Print("已恢复默认设置")
    end)

    NewButton(frame, "关闭", 100, 130, y, function()
        frame:Hide()
    end)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 22, 16)
    hint:SetText("提示：设置会保存在 QuestChainTipDB")
    hint:SetTextColor(0.6, 0.6, 0.6)

    frame:SetScript("OnShow", SyncControls)

    if UISpecialFrames then
        UISpecialFrames[#UISpecialFrames + 1] = PANEL_NAME
    end

    return frame
end

--------------------------------------------------------------------------------
-- 对外
--------------------------------------------------------------------------------

function O:Open()
    if not panel then
        panel = CreatePanel()
    end
    SyncControls()
    panel:Show()
end

function O:Toggle()
    if panel and panel:IsShown() then
        panel:Hide()
    else
        self:Open()
    end
end
