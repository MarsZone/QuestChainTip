--[[
设置界面：/qct 打开。所有改动即时生效（提示框正开着的话会立即重建面板）。
用自己画的控件（不用 OptionsSliderTemplate 之类），避免不同客户端版本模板缺失。
]]

local ADDON, ns = ...
local QCT = ns
local L = QCT.Locale

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
    -- 快捷键可能是自定义键，改完要重新绑到游戏按键上（或把旧绑定清掉）
    if QCT.Tooltip and QCT.Tooltip.ApplyChainKey then
        pcall(QCT.Tooltip.ApplyChainKey, QCT.Tooltip)
    end
    -- 宽度改了：悬停面板上面已由 Refresh 重建；详情窗开着的话要按新宽度重排
    if QCT.Window and QCT.Window.ApplyWidth then
        pcall(QCT.Window.ApplyWidth, QCT.Window)
    end
    -- 血量数值 / 小地图按钮：开关立刻生效
    if QCT.Health and QCT.Health.Refresh then
        pcall(QCT.Health.Refresh, QCT.Health)
    end
    if QCT.Minimap and QCT.Minimap.Refresh then
        pcall(QCT.Minimap.Refresh, QCT.Minimap)
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
-- 按键捕获（自定义快捷键）
--
-- 为什么要有：Questie 用 Shift，有人还想绑别的键。只给 Shift/Ctrl/Alt 三个选项
-- 仍然是「限制死」，所以这里让玩家直接按一下想用的键。
--
-- 捕获期间临时打开键盘，抓到一个非修饰键就结束；Esc 或点空白处取消。
-- 自定义键本身靠 SetBindingClick 绑到隐藏按钮上（见 Tooltip.ApplyChainKey）。
--------------------------------------------------------------------------------

local captureFrame

local function StopCapture()
    if not captureFrame then return end
    captureFrame:EnableKeyboard(false)
    captureFrame:Hide()
end

local function StartCapture(onDone)
    if not captureFrame then
        local frame = CreateFrame("Frame", "QuestChainTipKeyCapture", UIParent)
        frame:SetAllPoints(UIParent)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:EnableMouse(true)

        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0, 0, 0, 0.6)

        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
        title:SetPoint("CENTER", 0, 24)
        title:SetTextColor(1, 0.82, 0)

        local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        hint:SetPoint("CENTER", title, "BOTTOM", 0, -14)
        hint:SetTextColor(0.8, 0.8, 0.8)

        frame.title = title
        frame.hint = hint
        frame:Hide()

        frame:SetScript("OnMouseDown", StopCapture)
        frame:SetScript("OnKeyUp", function(self)
            -- 松键后把按键放行，避免捕获结束后游戏收不到键
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        end)
        frame:SetScript("OnKeyDown", function(self, key)
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            if key == "ESCAPE" then
                StopCapture()
                return
            end
            -- 只按下修饰键时不算数，等玩家按真正的键
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
                or key == "LALT" or key == "RALT" then
                return
            end

            local parts = {}
            if IsControlKeyDown and IsControlKeyDown() then parts[#parts + 1] = "CTRL" end
            if IsAltKeyDown and IsAltKeyDown() then parts[#parts + 1] = "ALT" end
            if IsShiftKeyDown and IsShiftKeyDown() then parts[#parts + 1] = "SHIFT" end
            parts[#parts + 1] = key
            local binding = table.concat(parts, "-")

            StopCapture()
            if onDone then pcall(onDone, binding) end
        end)

        captureFrame = frame
    end

    captureFrame.title:SetText(L["请按下一个按键"])
    captureFrame.hint:SetText(L["Esc 或点击空白处取消 · 自定义键会占用该键原本的绑定"])
    captureFrame:Show()
    captureFrame:EnableKeyboard(true)
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
    -- 比最初高 190px：多了两个快捷键、两行宽度和小地图图标，
    -- 底部按钮和提示语不能被挤到一起（1.5.26 去掉血量那两行，矮了 60px）
    frame:SetSize(WIDTH, 670)
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
    title:SetText(L["任务链提示 - 设置"])

    -- 版本号常驻右上角。玩家反馈「不知道装的是不是最新版」，光看界面看不出来。
    -- 值来自 toc 的 ## Version（QCT.VERSION），发版只改 toc 一处即可。
    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -22)
    version:SetText("v" .. tostring(QCT.VERSION or "?"))
    version:SetTextColor(0.55, 0.55, 0.55)
    frame.version = version

    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetTextColor(0.7, 0.7, 0.7)
    -- 文案里的按键是动态的（玩家可以改成 Ctrl / Alt），放进 SyncControls 里一起刷新
    controls[#controls + 1] = {
        kind = "mode",
        update = function()
            local key = (QCT.Tooltip and QCT.Tooltip.ChainKeyLabel and QCT.Tooltip.ChainKeyLabel()) or "Shift"
            subtitle:SetText(L.F(
                "在世界地图上悬停任务图标显示简介，按住 %s 打开整条任务链详情窗；小地图上不弹", key))
        end,
    }

    if UIPanelCloseButton then
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
    end

    local y = -60

    NewCheck(frame, L["启用插件"], "enabled", 22, y)
    y = y - ROW

    -- 1.5.26 起「血量数值显示」整个功能停用（会一直扫框体找血条，太费），
    -- 所以设置里这两行也一起撤掉了。

    -- 地图图标：默认收掉 Questie 的提示框，只留我们自己的框
    NewCheck(frame, L["地图图标只显示本插件的面板（隐藏 Questie 提示框）"], "hideQuestieTip", 22, y)
    y = y - ROW

    NewCheck(frame, L["显示小地图图标"], "minimap", 22, y)
    y = y - ROW

    -- 悬停面板显示范围：三态循环按钮
    NewLabel(frame, L["悬停面板"], 22, y + 3)
    local MODE_ORDER = { "off", "map", "all" }
    local MODE_LABEL = { off = L["不显示"], map = L["仅世界地图"], all = L["全部位置"] }
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

    -- 悬停面板宽度。原来写死 330，任务名/奖励物品一长就被迫折行，
    -- 玩家反馈「一行信息显示不全就被迫换行」。
    NewLabel(frame, L["悬停面板宽度"], 22, y + 3)
    local PANEL_WIDTH_ORDER = { 300, 380, 460 }
    local PANEL_WIDTH_LABEL = { [300] = L["窄"], [380] = L["标准"], [460] = L["宽"] }
    local panelWidthButton
    panelWidthButton = NewButton(frame, PANEL_WIDTH_LABEL[QCT.db.panelWidth or 380] or L["标准"], 120, 200, y, function()
        local current = tonumber(QCT.db.panelWidth) or 380
        local index = 2
        for i, value in ipairs(PANEL_WIDTH_ORDER) do
            if value == current then index = i end
        end
        QCT.db.panelWidth = PANEL_WIDTH_ORDER[index % #PANEL_WIDTH_ORDER + 1]
        panelWidthButton:SetText(PANEL_WIDTH_LABEL[QCT.db.panelWidth] or L["标准"])
        Apply()
    end)
    controls[#controls + 1] = {
        kind = "mode",
        update = function()
            panelWidthButton:SetText(PANEL_WIDTH_LABEL[tonumber(QCT.db.panelWidth) or 380] or L["标准"])
        end,
    }
    y = y - ROW

    -- 详情窗宽度。默认 AUTO 按屏幕宽度算，也可以钉死一个值。
    NewLabel(frame, L["详情窗宽度"], 22, y + 3)
    local WINDOW_WIDTH_ORDER = { "AUTO", 480, 580, 720 }
    local function WindowWidthLabel(value)
        if value == "AUTO" or value == nil or value == 0 then return L["自动"] end
        local numeric = tonumber(value)
        if numeric == 480 then return L["窄"] end
        if numeric == 720 then return L["宽"] end
        return L["标准"]
    end
    local windowWidthButton
    windowWidthButton = NewButton(frame, WindowWidthLabel(QCT.db.windowWidth), 120, 200, y, function()
        local current = QCT.db.windowWidth
        if current == nil then current = "AUTO" end
        local index = 1
        for i, value in ipairs(WINDOW_WIDTH_ORDER) do
            if value == current then index = i end
        end
        QCT.db.windowWidth = WINDOW_WIDTH_ORDER[index % #WINDOW_WIDTH_ORDER + 1]
        windowWidthButton:SetText(WindowWidthLabel(QCT.db.windowWidth))
        Apply()
    end)
    controls[#controls + 1] = {
        kind = "mode",
        update = function() windowWidthButton:SetText(WindowWidthLabel(QCT.db.windowWidth)) end,
    }
    y = y - ROW

    -- 详情窗快捷键。为什么可配：Questie 自己也用 Shift（地图上按住 Shift 切换被隐藏的任务标记），
    -- 默认值会跟它撞车，玩家按 Shift 想切 Questie 的隐藏任务，结果这边弹了个窗。
    NewLabel(frame, L["详情窗快捷键"], 22, y + 3)
    local KEY_ORDER = { "SHIFT", "CTRL", "ALT", "NONE" }
    local function KeyText(value)
        if value == "CTRL" then return "Ctrl" end
        if value == "ALT" then return "Alt" end
        if value == "NONE" then return L["不启用"] end
        if value == "SHIFT" or value == nil then return "Shift" end
        return value    -- 自定义键（"F" / "CTRL-1"）原样显示
    end
    local keyButton
    keyButton = NewButton(frame, KeyText(QCT.db.chainKey), 130, 190, y, function()
        local current = QCT.db.chainKey or "SHIFT"
        local index = 0     -- 自定义键不在列表里，点一下回到 Shift
        for i, value in ipairs(KEY_ORDER) do
            if value == current then index = i end
        end
        QCT.db.chainKey = KEY_ORDER[index % #KEY_ORDER + 1]
        keyButton:SetText(KeyText(QCT.db.chainKey))
        Apply()
    end)
    NewButton(frame, L["自定义…"], 92, 326, y, function()
        StartCapture(function(binding)
            QCT.db.chainKey = binding
            keyButton:SetText(KeyText(binding))
            Apply()
        end)
    end)
    controls[#controls + 1] = {
        kind = "mode",
        update = function() keyButton:SetText(KeyText(QCT.db.chainKey or "SHIFT")) end,
    }
    y = y - ROW

    -- 任务日志快捷键。任务日志里 Shift+点击是原生的「把任务链接贴到聊天框」，
    -- 所以这条路单独一个键，默认 Alt（Alt 在任务日志里没有原生用途）。
    NewLabel(frame, L["任务日志快捷键"], 22, y + 3)
    local QL_ORDER = { "ALT", "CTRL", "NONE" }
    local function QLText(value)
        if value == "CTRL" then return "Ctrl" end
        if value == "NONE" then return L["不启用"] end
        return "Alt"
    end
    local qlButton
    qlButton = NewButton(frame, QLText(QCT.db.questLogKey), 130, 190, y, function()
        local current = QCT.db.questLogKey or "ALT"
        local index = 1
        for i, value in ipairs(QL_ORDER) do
            if value == current then index = i end
        end
        QCT.db.questLogKey = QL_ORDER[index % #QL_ORDER + 1]
        qlButton:SetText(QLText(QCT.db.questLogKey))
        Apply()
    end)
    controls[#controls + 1] = {
        kind = "mode",
        update = function() qlButton:SetText(QLText(QCT.db.questLogKey or "ALT")) end,
    }
    y = y - ROW

    NewCheck(frame, L["显示任务描述"], "showDescription", 22, y)
    NewStepper(frame, L["描述最多行数"], "descLines", 1, 12, 200, y + 3)
    y = y - ROW

    NewCheck(frame, L["显示任务奖励（经验/金钱/物品/声望）"], "showRewards", 22, y)
    y = y - ROW

    NewCheck(frame, L["显示后续任务链"], "showChain", 22, y)
    y = y - ROW

    NewCheck(frame, L["后续任务每行显示奖励与状态"], "chainRewards", 40, y)
    y = y - ROW

    NewStepper(frame, L["普通状态显示层数"], "chainDepth", 1, 10, 40, y + 3)
    y = y - ROW

    NewStepper(frame, L["详情窗最多显示环数"], "chainDepthShift", 1, 40, 40, y + 3)
    y = y - ROW

    NewCheck(frame, L["显示前置任务"], "showPrereq", 22, y)
    y = y - ROW

    NewCheck(frame, L["聊天框显示诊断信息（排查问题时用）"], "diag", 22, y)
    y = y - ROW

    NewCheck(frame, L["调试输出（排查问题时用）"], "debug", 22, y)
    y = y - ROW - 8

    O.resetButton = NewButton(frame, L["恢复默认"], 100, 22, y, function()
        for key, value in pairs(QCT.Defaults or {}) do
            QCT.db[key] = value
        end
        SyncControls()
        Apply()
        QCT:Print(L["已恢复默认设置"])
    end)

    NewButton(frame, L["关闭"], 100, 130, y, function()
        frame:Hide()
    end)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 22, 16)
    hint:SetText(L["提示：设置会保存在 QuestChainTipDB"])
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
