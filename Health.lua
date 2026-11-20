--[[
血量数值：在目标 / 焦点框体的血条中央叠加「当前 / 最大」。

为什么单独一个文件：这功能和任务链完全无关，塞进 Tooltip.lua 只会让那个文件更难读。
默认关闭（设置里「显示血量数值」），玩家开了才建文字对象，关掉时立刻清空隐藏。

不碰框体本身的尺寸和布局：只在血条上叠一个 FontString，用 OVERLAY 层，
框体隐藏 / 目标消失时跟着一起消失。
]]

local ADDON, ns = ...
local QCT = ns
local L = QCT.Locale

local H = {}
QCT.Health = H

local UNITS = { "target", "focus" }

---unit -> { frame, bar, text, last }
local entries = {}

local function GetFont()
    local source = _G["GameTooltipTextLeft1"]
    if source and source.GetFont then
        local ok, path, size, flags = pcall(source.GetFont, source)
        if ok and path and size then return path, size, flags or "" end
    end
    return "Fonts\\ARKai_T.ttf", 12, ""
end

---框体里第一个 StatusBar 就是血条。
---不写死 TargetFrameTextureFrameHealthBar 这种名字：自定义 UI 会改结构，
---递归找更抗折腾（深度限 4 层，避免在大框体里乱爬）。
---@param mustContain string? 名字里必须包含的片段（先找 "Health"，避免把法力条当血条）
local function FindStatusBar(frame, depth, mustContain)
    depth = depth or 0
    if not frame or depth > 4 then return nil end

    if type(frame.GetObjectType) == "function" then
        local ok, kind = pcall(frame.GetObjectType, frame)
        if ok and kind == "StatusBar" then
            if not mustContain then return frame end
            local nameOk, name = pcall(function() return frame:GetName() end)
            if nameOk and type(name) == "string" and name:find(mustContain, 1, true) then
                return frame
            end
        end
    end

    if type(frame.GetChildren) == "function" then
        local ok, children = pcall(frame.GetChildren, frame)
        if ok and type(children) == "table" then
            for _, child in ipairs(children) do
                local found = FindStatusBar(child, depth + 1, mustContain)
                if found then return found end
            end
        end
    end
    return nil
end

local function UnitFrame(unit)
    if unit == "target" then return _G.TargetFrame end
    if unit == "focus" then return _G.FocusFrame end
    return nil
end

---给某个单位框体建一个叠在血条上的文字。框体不存在就返回 nil（下次再试）。
local function CreateEntry(unit)
    local frame = UnitFrame(unit)
    if not frame then return nil end

    local known = (unit == "target" and _G.TargetFrameTextureFrameHealthBar)
        or (unit == "focus" and _G.FocusFrameTextureFrameHealthBar)
    -- 先按名字找血条，再退回「第一个 StatusBar」——否则可能把法力条当血条
    local bar = known
        or FindStatusBar(frame, 0, "Health")
        or FindStatusBar(frame, 0, nil)
    if not bar then return nil end

    -- 文字必须建在血条自己身上，不能建在 TargetFrame 上：
    -- 血条是 TargetFrame 的子帧，子帧的绘制层级永远高于父帧的任何 layer，
    -- 挂在父帧 OVERLAY 上的文字会被血条整个盖住（玩家反馈「血量没显示」就是这个原因）。
    local text = bar:CreateFontString(nil, "OVERLAY")
    local path, size, flags = GetFont()
    if text.SetFont then text:SetFont(path, math.max(10, (size or 12) - 1), flags) end
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    if text.SetJustifyH then text:SetJustifyH("CENTER") end
    text:SetTextColor(1, 1, 1)
    -- 和 tooltip 一样加 1px 阴影：血条底色是深红，纯白字在缩放后容易糊
    if text.SetShadowColor then text:SetShadowColor(0, 0, 0, 1) end
    if text.SetShadowOffset then text:SetShadowOffset(1, -1) end
    text:SetText("")

    local entry = { frame = frame, bar = bar, text = text, last = "" }
    entries[unit] = entry
    return entry
end

local function UpdateUnit(unit)
    if not (QCT.db and QCT.db.showHealth) then return end

    local entry = entries[unit] or CreateEntry(unit)
    if not entry then return end

    local exists = type(UnitExists) == "function" and UnitExists(unit)
    if not exists then
        if entry.last ~= "" then
            entry.text:SetText("")
            entry.last = ""
        end
        return
    end

    local cur = tonumber(UnitHealth(unit)) or 0
    local max = tonumber(UnitHealthMax(unit)) or 0
    if max <= 0 then return end

    local value = string.format("%d / %d", cur, max)
    if value ~= entry.last then
        entry.text:SetText(value)
        entry.last = value
    end
end

local function UpdateAll()
    for _, unit in ipairs(UNITS) do
        local ok, err = pcall(UpdateUnit, unit)
        if not ok and QCT.Log then QCT.Log:Add("health", "更新失败:", unit, tostring(err)) end
    end
end

function H:Enable()
    self.enabled = true
    for _, unit in ipairs(UNITS) do
        local entry = entries[unit] or CreateEntry(unit)
        if entry then entry.text:Show() end
    end
    UpdateAll()
end

function H:Disable()
    self.enabled = false
    for _, entry in pairs(entries) do
        entry.text:SetText("")
        entry.text:Hide()
        entry.last = ""
    end
end

---设置里改完开关后调用
function H:Refresh()
    if QCT.db and QCT.db.showHealth then
        self:Enable()
    else
        self:Disable()
    end
end

function H:Init()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:SetScript("OnEvent", function(_, event, unit)
        if not (QCT.db and QCT.db.showHealth) then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            if unit == "target" or unit == "focus" then
                local ok, err = pcall(UpdateUnit, unit)
                if not ok and QCT.Log then QCT.Log:Add("health", "事件更新失败:", tostring(err)) end
            end
            return
        end
        UpdateAll()
    end)
    self.eventFrame = frame
    self:Refresh()
end
