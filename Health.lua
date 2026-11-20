--[[
血量数值：在目标 / 焦点框体的血条中央叠加「当前 / 最大」。

为什么单独一个文件：这功能和任务链完全无关，塞进 Tooltip.lua 只会让那个文件更难读。
默认关闭（设置里「显示血量数值」），玩家开了才建文字对象，关掉时立刻清空隐藏。

1.5.18 重写了框体查找。上一版直接拿 _G.TargetFrame，然后在里面递归找第一个 StatusBar；
在装了 pfUI 这类自绘 UI 的客户端上全军覆没：
  * 暴雪的 TargetFrame 还在，但整条父链被隐藏了 —— 文字挂上去，屏幕上什么也看不见；
  * 自绘框体的血条可能不是 StatusBar（Frame + 贴图做的），递归找不到；
  * 血条找到了但和法力条长得一样，挑错就把数字叠到蓝条上。
现在改成：先收集候选框体（默认框体 / pfUI.uf / 扫 UIParent 找 unit 字段），
只挑**当前真的可见**的那个，血条按名字优先、其次按面积挑，实在没有就在框体上盖一层独立 Frame。
]]

local ADDON, ns = ...
local QCT = ns
local L = QCT.Locale

local H = {}
QCT.Health = H

local UNITS = { "target", "focus" }

---unit -> { frame, bar, text, last }
local entries = {}

---这个客户端上有些值是 secret value（外来帧的文本、受保护单位的数值），
---直接 tostring / 比较会抛错，整个函数跟着炸。所有输出都走这里兜一层。
local function Safe(value)
    if value == nil then return "nil" end
    local ok, text = pcall(tostring, value)
    if ok then return text end
    return "<secret>"
end

local function FrameName(frame)
    if not frame then return "?" end
    if type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "<无名>"
end

local function IsShownSelf(frame)
    if not frame or type(frame.IsShown) ~= "function" then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown and true or false
end

---这个帧（含所有祖先）现在是不是真的看得见。
---必须往上看祖先：pfUI 会把暴雪的 TargetFrame 留着不删、只把整条父链隐藏掉，
---这时候 TargetFrame:IsShown() 还是 true，但玩家屏幕上什么都没有。
local function IsVisibleChain(frame)
    local node, depth = frame, 0
    while node and depth < 8 do
        if type(node.IsShown) == "function" then
            local ok, shown = pcall(node.IsShown, node)
            if ok and not shown then return false end
        end
        local ok, parent = pcall(function() return node:GetParent() end)
        node = ok and parent or nil
        depth = depth + 1
    end
    return true
end

local function GetFont()
    local source = _G["GameTooltipTextLeft1"]
    if source and source.GetFont then
        local ok, path, size, flags = pcall(source.GetFont, source)
        if ok and path and size then return path, size, flags or "" end
    end
    return "Fonts\\ARKai_T.ttf", 12, ""
end

--------------------------------------------------------------------------------
-- 找血条
--------------------------------------------------------------------------------

---递归收集框体里所有 StatusBar（深度限 4 层，避免在大框体里乱爬）
local function FindStatusBars(frame, depth, out)
    if not frame or depth > 4 then return end

    if type(frame.GetObjectType) == "function" then
        local ok, kind = pcall(frame.GetObjectType, frame)
        if ok and kind == "StatusBar" then out[#out + 1] = frame end
    end

    if type(frame.GetChildren) == "function" then
        local ok, children = pcall(frame.GetChildren, frame)
        if ok and type(children) == "table" then
            for _, child in ipairs(children) do
                FindStatusBars(child, depth + 1, out)
            end
        end
    end
end

---框体的血条。
---顺序：暴雪默认命名 → 名字里带 Health/hp 的 → 面积最大的那个。
---不能直接拿「第一个 StatusBar」：法力条、施法条也是 StatusBar，挑错就把数字叠到蓝条上了。
local function PickHealthBar(frame)
    if not frame then return nil end

    -- 暴雪默认框体：TargetFrame -> TargetFrameTextureFrameHealthBar，最快也最准
    local name = FrameName(frame)
    if name ~= "<无名>" and name ~= "?" then
        local named = _G[name .. "TextureFrameHealthBar"]
        if named and type(named.GetObjectType) == "function" then
            local ok, kind = pcall(named.GetObjectType, named)
            if ok and kind == "StatusBar" then return named end
        end
    end

    local bars = {}
    FindStatusBars(frame, 0, bars)
    if #bars == 0 then return nil end

    local best, bestArea = nil, -1
    for _, bar in ipairs(bars) do
        local barName = FrameName(bar)
        if barName:find("Health", 1, true) or barName:find("_hp", 1, true)
            or barName:find("health", 1, true) then
            return bar
        end

        local w, h = 0, 0
        if type(bar.GetWidth) == "function" then
            local ok, value = pcall(bar.GetWidth, bar)
            if ok and type(value) == "number" then w = value end
        end
        if type(bar.GetHeight) == "function" then
            local ok, value = pcall(bar.GetHeight, bar)
            if ok and type(value) == "number" then h = value end
        end
        if w * h > bestArea then best, bestArea = bar, w * h end
    end
    return best
end

--------------------------------------------------------------------------------
-- 找框体
--------------------------------------------------------------------------------

---所有可能是「这个单位的框体」的帧，按优先级排。
local function Candidates(unit)
    local list, seen = {}, {}
    local function add(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            list[#list + 1] = frame
        end
    end

    -- 1) 暴雪默认框体
    add(unit == "target" and _G.TargetFrame or _G.FocusFrame)

    -- 2) pfUI 这类 UI 包：单位框体挂在 pfUI.uf 下面
    local pf = _G.pfUI
    if type(pf) == "table" and type(pf.uf) == "table" then add(pf.uf[unit]) end

    -- 3) 兜底：在 UIParent 里扫一遍，找 unit 字段对得上、而且当前可见的
    local function scan(parent, depth)
        if depth > 3 or not parent or type(parent.GetChildren) ~= "function" then return end
        local ok, children = pcall(parent.GetChildren, parent)
        if not ok or type(children) ~= "table" then return end
        for _, child in ipairs(children) do
            local uok, value = pcall(function() return child.unit end)
            if uok and value == unit and IsVisibleChain(child) then add(child) end
            scan(child, depth + 1)
        end
    end
    scan(_G.UIParent, 0)

    return list
end

---挑一个「现在真的看得见」的框体 + 血条。
---@return table? frame, table? bar
local function ResolveHost(unit)
    local candidates = Candidates(unit)
    local fallbackFrame, fallbackBar, fallbackVisible

    for _, frame in ipairs(candidates) do
        local bar = PickHealthBar(frame)
        if bar then
            if IsVisibleChain(bar) then return frame, bar end
            -- 找到了血条但看不见（被 UI 包隐藏的暴雪框体）：留着当兜底
            fallbackFrame = fallbackFrame or frame
            fallbackBar = fallbackBar or bar
        elseif IsVisibleChain(frame) then
            fallbackVisible = fallbackVisible or frame
        end
    end

    if fallbackFrame then return fallbackFrame, fallbackBar end
    if fallbackVisible then return fallbackVisible, nil end
    return candidates[1], nil
end

--------------------------------------------------------------------------------
-- 建文字
--------------------------------------------------------------------------------

---给某个单位建一个叠在血条上的文字。框体不存在就返回 nil（下次再试）。
local function CreateEntry(unit, frame, bar)
    frame = frame or ResolveHost(unit)
    if not frame then return nil end
    if not bar then bar = PickHealthBar(frame) end

    local text
    if bar then
        -- 文字必须建在血条自己身上，不能建在 TargetFrame 上：
        -- 血条是 TargetFrame 的子帧，子帧的绘制层级永远高于父帧的任何 layer，
        -- 挂在父帧 OVERLAY 上的文字会被血条整个盖住。
        text = bar:CreateFontString(nil, "OVERLAY")
        QCT.Log:Add("health", unit, "文字挂血条 |", FrameName(bar))
    else
        -- 兜底：有些自定义 UI 的血条不是 StatusBar（Frame + 贴图做的），递归找不到。
        -- 这时在框体上叠一层独立 Frame，层级抬到所有子帧之上，文字放框体中央。
        -- 位置不完美，但至少能看见，也好过完全不显示。
        local overlay = CreateFrame("Frame", nil, frame)
        if overlay.SetAllPoints then overlay:SetAllPoints(frame) end
        if overlay.SetFrameLevel and frame.GetFrameLevel then
            local ok, level = pcall(frame.GetFrameLevel, frame)
            overlay:SetFrameLevel((ok and tonumber(level) or 1) + 50)
        end
        text = overlay:CreateFontString(nil, "OVERLAY")
        QCT.Log:Add("health", unit, "没找到血条，用框体中央兜底 |", FrameName(frame))
    end

    local path, size, flags = GetFont()
    if text.SetFont then text:SetFont(path, math.max(10, (size or 12) - 1), flags) end
    text:SetPoint("CENTER", bar or text:GetParent(), "CENTER", 0, 0)
    if text.SetJustifyH then text:SetJustifyH("CENTER") end
    -- 不设宽度的话，某些客户端上 FontString 会按 0 宽排版，字挤成一条看不见
    if text.SetWidth then text:SetWidth(220) end
    text:SetTextColor(1, 1, 1)
    -- 和 tooltip 一样加 1px 阴影：血条底色是深红，纯白字在缩放后容易糊
    if text.SetShadowColor then text:SetShadowColor(0, 0, 0, 1) end
    if text.SetShadowOffset then text:SetShadowOffset(1, -1) end
    -- 顶到 OVERLAY 的最高子层：pfUI 这类 UI 包自己的血量文字也在 OVERLAY，
    -- 不抬子层的话谁后画谁在上，我们的字可能被盖住
    if text.SetDrawLayer then pcall(text.SetDrawLayer, text, "OVERLAY", 7) end
    text:SetText("")

    local entry = { frame = frame, bar = bar, text = text, last = "" }
    entries[unit] = entry
    return entry
end

--------------------------------------------------------------------------------
-- 更新
--------------------------------------------------------------------------------

local function NumberOf(fn, unit)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, unit)
    if not ok then return nil end
    local nok, num = pcall(tonumber, value)
    if nok and type(num) == "number" then return num end
    return nil
end

local function UnitExistsSafe(unit)
    if type(UnitExists) ~= "function" then return NumberOf(UnitHealth, unit) ~= nil end
    local ok, value = pcall(UnitExists, unit)
    if ok then
        -- 这个客户端上「单位是否存在」的返回值可能是 secret value，比较会抛错，所以再包一层
        local cok, truthy = pcall(function() return value and true or false end)
        if cok then return truthy end
    end
    -- 比较被拒绝（secret value）：退回看血量能不能取到
    return NumberOf(UnitHealth, unit) ~= nil
end

---现在的框体还能用就返回；看不见了就重新挑一个（换目标、UI 包刚建好自绘框体都会走到这里）。
---重新挑的代价是一次 UIParent 扫描，所以限流 3 秒一次，别让 UNIT_HEALTH 把帧数打爆。
local lastResolve = {}

local function EnsureEntry(unit)
    local entry = entries[unit]

    if entry and IsVisibleChain(entry.frame) then return entry end

    local now = type(GetTime) == "function" and GetTime() or 0
    if entry and (now - (lastResolve[unit] or 0)) < 3 then return entry end
    lastResolve[unit] = now

    local frame, bar = ResolveHost(unit)
    if not frame then return entry end
    if entry and entry.frame == frame and entry.bar == bar then return entry end

    if entry then
        if entry.text and entry.text.Hide then pcall(entry.text.Hide, entry.text) end
        entries[unit] = nil
    end
    return CreateEntry(unit, frame, bar)
end

local function UpdateUnit(unit)
    if not (QCT.db and QCT.db.showHealth) then return end

    local entry = entries[unit]

    if not UnitExistsSafe(unit) then
        if entry and entry.last ~= "" then
            entry.text:SetText("")
            entry.last = ""
        end
        return
    end

    entry = EnsureEntry(unit)
    if not entry then return end

    local cur = NumberOf(UnitHealth, unit)
    local max = NumberOf(UnitHealthMax, unit)
    if not cur or not max or max <= 0 then return end

    local value = string.format("%d / %d", cur, max)
    if value ~= entry.last then
        entry.text:SetText(value)
        entry.last = value
    end
end

local function UpdateAll()
    for _, unit in ipairs(UNITS) do
        local ok, err = pcall(UpdateUnit, unit)
        if not ok and QCT.Log then QCT.Log:Add("health", "更新失败:", unit, Safe(err)) end
    end
end

function H:Enable()
    self.enabled = true
    for _, unit in ipairs(UNITS) do
        local old = entries[unit]
        if old and old.text and old.text.Hide then pcall(old.text.Hide, old.text) end
        entries[unit] = nil
        lastResolve[unit] = nil
        local entry = CreateEntry(unit)
        if entry then entry.text:Show() end
    end
    UpdateAll()
end

function H:Disable()
    self.enabled = false
    for _, entry in pairs(entries) do
        if entry.text then
            entry.text:SetText("")
            entry.text:Hide()
        end
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
                if not ok and QCT.Log then QCT.Log:Add("health", "事件更新失败:", Safe(err)) end
            end
            return
        end
        UpdateAll()
    end)
    self.eventFrame = frame
    self:Refresh()
end

---`/qct health` 和测试用：拿到某个单位当前的挂载记录
---@param unit string
---@return table?
function H:GetEntry(unit)
    return entries[unit]
end

---`/qct health` 用：把「框体找没找到 / 血条找没找到 / 文字状态」全打出来。
---玩家反馈「血量不显示」时，光看代码猜不出来，得看实际结构。
---整段包 pcall：这个客户端上随便哪个返回值是 secret value，诊断本身就先炸了，
---上一版就是这样——只打出「开关: true」两行，后面的全没了，等于没诊断。
function H:Diagnose()
    QCT:Print("---- 血量诊断 ----")
    QCT:Print("开关:", Safe(QCT.db and QCT.db.showHealth))

    for _, unit in ipairs(UNITS) do
        local ok, err = pcall(function()
            local exists = UnitExistsSafe(unit)
            local cur = NumberOf(UnitHealth, unit)
            local max = NumberOf(UnitHealthMax, unit)

            QCT:Print(unit, "| 单位存在:", Safe(exists),
                "| 血量:", Safe(cur), "/", Safe(max))

            local entry = entries[unit]
            if entry then
                local visible = "?"
                if entry.text and type(entry.text.IsVisible) == "function" then
                    local vok, value = pcall(entry.text.IsVisible, entry.text)
                    visible = vok and Safe(value) or "?"
                end
                local tok, text = pcall(function() return entry.text:GetText() end)
                QCT:Print("  文字:", tok and Safe(text) or "<读不到>",
                    "| 可见:", visible,
                    "| 挂在:", FrameName(entry.bar or entry.frame))
            else
                QCT:Print("  文字: 还没创建")
            end

            -- 候选框体一览：玩家装了自绘 UI 时，看这一行就知道该往哪儿挂
            local candidates = Candidates(unit)
            local parts = {}
            for i, frame in ipairs(candidates) do
                if i > 6 then break end
                local bar = PickHealthBar(frame)
                parts[#parts + 1] = FrameName(frame)
                    .. (IsVisibleChain(frame) and "[显示]" or "[隐藏]")
                    .. (bar and ("+血条:" .. FrameName(bar)) or "+无血条")
            end
            QCT:Print("  候选框体:", #parts > 0 and table.concat(parts, " ; ") or "一个都没找到")

            local frame, bar = ResolveHost(unit)
            QCT:Print("  最终选用:", FrameName(frame), "| 血条:", FrameName(bar))
        end)
        if not ok then
            QCT:Print("  |cffff0000" .. unit .. " 诊断出错: " .. Safe(err) .. "|r")
        end
    end
end
