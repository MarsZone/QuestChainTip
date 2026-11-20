--[[
小地图按钮：点一下打开设置，拖到任意位置（角度记在 db.minimapAngle）。

为什么自己画而不用 LibDBIcon：本客户端没有那个库，为了一个小按钮打包整个库不值得。
结构照着 LibDBIcon 来：Button 挂在 Minimap 下，按角度环绕，图标 + 追踪边框。
]]

local ADDON, ns = ...
local QCT = ns
local L = QCT.Locale

local M = {}
QCT.Minimap = M

local BUTTON_NAME = "QuestChainTipMinimapButton"
local ICON_TEXTURE = "Interface\\AddOns\\QuestChainTip\\Media\\QuestChainTip.tga"
local DEFAULT_ANGLE = 220      -- 度，从 12 点方向顺时针（左下，避开追踪/日历按钮）

-- Lua 5.1 有 math.atan2；5.3+ 改成 math.atan(y, x)
local atan2 = math.atan2 or math.atan

local function GetAngle()
    local value = tonumber(QCT.db and QCT.db.minimapAngle)
    if value == nil then return DEFAULT_ANGLE end
    return value
end

---按钮现在是不是还被小地图「拥有」。
---小地图按钮收集器（MBB / MinimapButtonBag 之类）会把按钮 SetParent 到自己的网格里，
---接管位置和显示。这时我们要是还按角度往小地图边缘摆，就会出现
---「网格里留一个空格子、图标飘在外面」的怪样子（玩家截图反馈的就是这个）。
local function StillOnMinimap(button)
    local minimap = _G.Minimap
    if not minimap or not button then return false end
    if type(button.GetParent) ~= "function" then return true end
    local ok, parent = pcall(button.GetParent, button)
    if not ok then return true end
    return parent == minimap
end

---按当前角度把小按钮摆到小地图边缘
local function Place(button)
    local minimap = _G.Minimap
    if not minimap or not button then return end
    if not StillOnMinimap(button) then return end

    local width = 140
    if type(minimap.GetWidth) == "function" then
        local ok, value = pcall(minimap.GetWidth, minimap)
        if ok and tonumber(value) and value > 0 then width = value end
    end

    local radius = width / 2 + 6
    local angle = math.rad(GetAngle())
    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

---拖动：跟着鼠标相对小地图圆心的角度走
local function FollowCursor(button)
    local minimap = _G.Minimap
    if not minimap then return end
    if not StillOnMinimap(button) then return end
    if type(GetCursorPosition) ~= "function" then return end

    local mx, my = minimap:GetCenter()
    local px, py = GetCursorPosition()
    if not (mx and my and px and py) then return end

    local scale = minimap.GetEffectiveScale and minimap:GetEffectiveScale() or 1
    if not scale or scale == 0 then scale = 1 end
    px, py = px / scale, py / scale

    local angle = math.deg(atan2(py - my, px - mx))
    if angle ~= angle then return end     -- NaN 保护
    QCT.db.minimapAngle = angle
    Place(button)
end

function M:Create()
    if self.button then return self.button end

    local minimap = _G.Minimap
    if not minimap then return nil end

    local button = CreateFrame("Button", BUTTON_NAME, minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.icon = icon

    -- 和小地图其它按钮同款的圆环边框，不然看着像贴上去的一块方图
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)

    if button.SetHighlightTexture then
        pcall(button.SetHighlightTexture, button,
            "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    end

    button:SetScript("OnEnter", function(self)
        local tip = _G.GameTooltip
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_LEFT")
        tip:AddLine(L["任务链提示"])
        tip:AddLine(L["左键打开设置"], 1, 1, 1)
        tip:AddLine(L["拖动可调整位置"], 0.7, 0.7, 0.7)
        tip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        local tip = _G.GameTooltip
        if not tip or not tip.IsShown or not tip:IsShown() then return end
        -- 只关自己开的那个，别把别人的提示框（物品、技能）一起关掉
        local owner
        if type(tip.GetOwner) == "function" then
            local ok, value = pcall(tip.GetOwner, tip)
            if ok then owner = value end
        end
        if owner == self then tip:Hide() end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(frame)
            FollowCursor(frame)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" or mouseButton == "RightButton" then
            if QCT.Options then QCT.Options:Open() end
        end
    end)
    button:SetScript("OnShow", function(self)
        Place(self)
    end)

    self.button = button
    Place(button)
    return button
end

function M:Show()
    local button = self:Create()
    if button then button:Show() end
end

function M:Hide()
    if self.button then self.button:Hide() end
end

---设置里改完「显示小地图图标」后调用
function M:Refresh()
    if QCT.db and QCT.db.minimap then
        self:Show()
    else
        self:Hide()
    end
end

function M:Init()
    self:Create()
    self:Refresh()
end
