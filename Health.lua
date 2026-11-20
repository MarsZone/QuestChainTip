--[[
血量数值：在目标 / 焦点框体的血条中央叠加「当前 / 最大」。

为什么单独一个文件：这功能和任务链完全无关，塞进 Tooltip.lua 只会让那个文件更难读。
默认关闭（设置里「显示血量数值」），玩家开了才建文字对象，关掉时立刻清空隐藏。

1.5.19 改了两件大事，都是被真实报错逼出来的：

一、**不能把血量拼成字符串**
   这个客户端把 UnitHealth / UnitHealthMax 的返回值标成 secret value。
   `string.format("%d / %d", cur, max)` 一执行就抛 "attempt to use a secret value"，
   所以 1.5.15~1.5.18 一直在「框体找不到 / 层级不对」上打转，方向完全错了 ——
   真正的原因是我们自己那行 format 就炸了，文字根本没被设置过。
   现在改成三段独立文字：「当前值」「/」「最大值」，各自把**原始值**直接交给
   FontString:SetText（secret value 只允许这样「显示」，不允许读出来加工）。

二、**框体不能只看 _G.TargetFrame**
   装了 pfUI 这类自绘 UI 时，暴雪的 TargetFrame 还在，但整条父链被隐藏 ——
   文字挂上去屏幕上什么也没有；自绘血条还可能是 Frame + 贴图做的，不是 StatusBar。
   现在先收集候选框体（默认框体 / pfUI.uf / 扫 UIParent 找 unit 字段），
   只挑当前真的可见的那个，血条按名字优先、其次按面积挑，实在没有就在框体上盖一层独立 Frame。
]]

local ADDON, ns = ...
local QCT = ns
local L = QCT.Locale

local H = {}
QCT.Health = H

local UNITS = { "target", "focus" }

---unit -> { frame, bar, cur, sep, max, blocked }
local entries = {}

--------------------------------------------------------------------------------
-- 安全取值
--------------------------------------------------------------------------------

---secret value 对 tostring() 不报错、只是原样返回，真正抛错的是之后的拼接/格式化。
---探针必须用真正会触发检查的操作：`.. ""` 在这个客户端上会被当恒等运算放过，
---所以同时用 `.. "x"`、string.format、string.len 三道。
local function Safe(value)
    if value == nil then return "nil" end
    local ok, text = pcall(tostring, value)
    if not ok then return "<secret>" end
    local probeOk = pcall(function()
        local probe = text .. "x"
        probe = string.format("%s", probe)
        return string.len(probe) > 0
    end)
    if probeOk then return text end
    return "<secret>"
end

local function FrameName(frame)
    if not frame then return "?" end
    if type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    -- 无名帧把对象类型带上：排查时至少能分清它是 Frame 还是 StatusBar
    if type(frame.GetObjectType) == "function" then
        local ok, kind = pcall(frame.GetObjectType, frame)
        if ok and type(kind) == "string" then return "<无名" .. kind .. ">" end
    end
    return "<无名>"
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

---框体够不够大。扫 UIParent 时会有很多 0 尺寸的辅助帧，它们的 unit 字段可能也是 "target"，
---不筛掉就会把文字挂到一个看不见的小方块上。
local function BigEnough(frame)
    local w, h = 0, 0
    if type(frame.GetWidth) == "function" then
        local ok, value = pcall(frame.GetWidth, frame)
        if ok and type(value) == "number" then w = value end
    end
    if type(frame.GetHeight) == "function" then
        local ok, value = pcall(frame.GetHeight, frame)
        if ok and type(value) == "number" then h = value end
    end
    return w >= 40 and h >= 15
end

---名字看起来像不像这个单位的框体（pfUI_uf_target、SUF_Target、oUF_Target…）。
---光靠 `child.unit == "target"` 不够：有的 UI 包不给帧设 unit 字段，
---但名字一般还是以 target / focus 结尾。
---只认后缀，避免把 TargetFrameSpellBar、TargetFrameTextureFrameHealthBar 这种子帧认进来。
local function NameLooksLike(unit, name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    if unit == "target" then return lower:match("target$") ~= nil end
    return lower:match("focus$") ~= nil
end

---把客户端里所有帧过一遍。
---
---为什么需要它：玩家的目标框（左上角那个）既不在 UIParent 下、也没有名字，
---只扫 UIParent 永远扫不到 —— `/qct health scan` 在玩家机器上只列出了一个 TargetFrame，
---而他真正在看的那个框连名字都没有。EnumerateFrames 是客户端提供的全量遍历，
---不管帧有没有名字、挂在谁下面，都能拿到。
local function ForEachFrame(fn)
    if type(EnumerateFrames) ~= "function" then return false end
    local guard = 0
    local ok = pcall(function()
        local current = nil
        while true do
            local nextFrame = EnumerateFrames(current)
            if not nextFrame then break end
            current = nextFrame
            guard = guard + 1
            if guard > 30000 then break end
            fn(nextFrame)
        end
    end)
    return ok
end

---目标自己的姓名板。
---
---这是 1.5.23 的关键发现：无限服 1.60.1 是**现代 API 的客户端**（有 C_NamePlate、
---有 C_QuestLog，但没有 8.0 就删掉的 GetQuestLogSelection）。
---玩家截图里那个「左上角的目标框」其实是**敌方单位姓名板** ——
---`C_NamePlate.GetNamePlateForUnit("target")` 能直接把目标那块牌子拿到手，
---血条就在 plate.UnitFrame.healthBar 上，数字挂上去就跟着牌子走。
local function NamePlateFor(unit)
    local api = _G.C_NamePlate
    if type(api) ~= "table" or type(api.GetNamePlateForUnit) ~= "function" then return nil end
    local ok, plate = pcall(api.GetNamePlateForUnit, unit)
    if not ok or not plate then return nil end
    return plate
end

---所有可能是「这个单位的框体」的帧，按优先级排。
---
---**自绘 UI 的框体排在暴雪默认框体前面**，这是 1.5.20 改的：
---玩家装了自绘 UI 时，暴雪的 TargetFrame 往往还留着（甚至还在显示），
---而玩家真正盯着看的是 UI 包自己那个框体。之前把 _G.TargetFrame 排第一，
---结果血量数字叠在了玩家根本不看的那一个上面（实测：数字出现在屏幕右下角的默认框体上，
---而玩家要的是左上角 UI 包那个）。
local function Candidates(unit)
    local list, seen = {}, {}
    local function add(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            list[#list + 1] = frame
        end
    end

    -- 手动指定优先（/qct health <帧名> 用）
    if H.forced and H.forced[unit] then add(H.forced[unit]) end

    local blizzard = (unit == "target") and _G.TargetFrame or _G.FocusFrame

    -- 1) 目标自己的姓名板排第一。
    --    这个客户端的目标框就是姓名板（客户端自己画的、Lua 拿不到），
    --    而姓名板本身是 Lua 帧，能直接挂 —— 玩家看到的就是它。
    local plate = NamePlateFor(unit)
    if plate then
        add(plate)
        local pok, unitFrame = pcall(function() return plate.UnitFrame end)
        if pok and unitFrame and unitFrame ~= plate then add(unitFrame) end
    end

    -- 2) pfUI 这类 UI 包：单位框体挂在 pfUI.uf 下面
    local pf = _G.pfUI
    if type(pf) == "table" and type(pf.uf) == "table" then
        local frame = pf.uf[unit]
        if frame ~= blizzard then add(frame) end
    end

    -- 3) 兜底：在 UIParent 里扫一遍。两个判据取并集 ——
    --    unit 字段对得上，或者名字以 target / focus 结尾。
    local function scan(parent, depth)
        if depth > 3 or not parent or type(parent.GetChildren) ~= "function" then return end
        local ok, children = pcall(parent.GetChildren, parent)
        if not ok or type(children) ~= "table" then return end
        for _, child in ipairs(children) do
            if child ~= blizzard and IsVisibleChain(child) and BigEnough(child) then
                local uok, value = pcall(function() return child.unit end)
                local nok, name = pcall(child.GetName, child)
                local byUnit = uok and value == unit
                local byName = nok and NameLooksLike(unit, name)
                if byUnit or byName then add(child) end
            end
            scan(child, depth + 1)
        end
    end
    scan(_G.UIParent, 0)

    -- 4) 前面一无所获（只剩下暴雪默认框体）就全量遍历一次。
    --      这一遍要过几千个帧，代价大，所以只在「一个自绘候选都没找到」时才做。
    local custom = false
    for _, frame in ipairs(list) do
        if frame ~= blizzard then
            custom = true
            break
        end
    end
    if not custom then
        ForEachFrame(function(child)
            if child == blizzard then return end
            local uok, value = pcall(function() return child.unit end)
            if not (uok and value == unit) then return end
            if IsVisibleChain(child) and BigEnough(child) then add(child) end
        end)
    end

    -- 5) 暴雪默认框体放最后
    add(blizzard)

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
--
-- 三段独立 FontString，而不是一个「2182 / 2182」：
-- 这个客户端的血量是 secret value，参与任何字符串拼接/格式化都会抛错，
-- 但 SetText 是允许的出口 —— 把原始值直接喂进去，客户端自己会渲染成数字。
-- 中间的「/」是静态文字，不需要读血量。
--------------------------------------------------------------------------------

local SEGMENT_GAP = 6

---@param host table 血条（找不到血条时是覆盖帧）
local function MakeSegment(host, justify, x)
    local fontString = host:CreateFontString(nil, "OVERLAY")

    local path, size, flags = GetFont()
    if fontString.SetFont then
        fontString:SetFont(path, math.max(10, (size or 12) - 1), flags)
    end
    if fontString.SetJustifyH then fontString:SetJustifyH(justify) end
    -- 不设宽度的话，某些客户端上 FontString 会按 0 宽排版，字挤成一条看不见
    if fontString.SetWidth then fontString:SetWidth(220) end
    fontString:SetTextColor(1, 1, 1)
    -- 血条底色是深红，纯白字在缩放后容易糊，加 1px 阴影
    if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 1) end
    if fontString.SetShadowOffset then fontString:SetShadowOffset(1, -1) end
    -- 顶到 OVERLAY 的最高子层：pfUI 自己的血量文字也在 OVERLAY，
    -- 不抬子层的话谁后画谁在上，我们的字可能被盖住
    if fontString.SetDrawLayer then pcall(fontString.SetDrawLayer, fontString, "OVERLAY", 7) end

    if justify == "RIGHT" then
        fontString:SetPoint("RIGHT", host, "CENTER", -x, 0)
    elseif justify == "LEFT" then
        fontString:SetPoint("LEFT", host, "CENTER", x, 0)
    else
        fontString:SetPoint("CENTER", host, "CENTER", 0, 0)
    end
    return fontString
end

---给某个单位建三个文字段。框体不存在就返回 nil（下次再试）。
local function CreateEntry(unit, frame, bar)
    frame = frame or ResolveHost(unit)
    if not frame then return nil end
    if not bar then bar = PickHealthBar(frame) end

    local host
    if bar then
        -- 文字必须建在血条自己身上，不能建在 TargetFrame 上：
        -- 血条是 TargetFrame 的子帧，子帧的绘制层级永远高于父帧的任何 layer，
        -- 挂在父帧 OVERLAY 上的文字会被血条整个盖住。
        host = bar
        QCT.Log:Add("health", unit, "文字挂血条 |", FrameName(bar))
    else
        -- 兜底：有些自定义 UI 的血条不是 StatusBar（Frame + 贴图做的），递归找不到。
        -- 这时在框体上叠一层独立 Frame，层级抬到所有子帧之上，文字放框体中央。
        local overlay = CreateFrame("Frame", nil, frame)
        if overlay.SetAllPoints then overlay:SetAllPoints(frame) end
        if overlay.SetFrameLevel and frame.GetFrameLevel then
            local ok, level = pcall(frame.GetFrameLevel, frame)
            overlay:SetFrameLevel((ok and tonumber(level) or 1) + 50)
        end
        host = overlay
        QCT.Log:Add("health", unit, "没找到血条，用框体中央兜底 |", FrameName(frame))
    end

    local entry = {
        frame = frame,
        bar = bar,
        cur = MakeSegment(host, "RIGHT", SEGMENT_GAP),
        sep = MakeSegment(host, "CENTER", 0),
        max = MakeSegment(host, "LEFT", SEGMENT_GAP),
    }
    entry.sep:SetText("/")
    entry.cur:SetText("")
    entry.max:SetText("")

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
    -- 这里故意不 tonumber：secret value 过一遍 tonumber 还是 secret，
    -- 能不能用只能交给 SetText 去试
    return value
end

local function UnitExistsSafe(unit)
    if type(UnitExists) ~= "function" then return NumberOf(UnitHealth, unit) ~= nil end
    local ok, value = pcall(UnitExists, unit)
    if ok then
        local cok, truthy = pcall(function() return value and true or false end)
        if cok then return truthy end
    end
    return NumberOf(UnitHealth, unit) ~= nil
end

---把原始值交给 SetText。返回 false 表示这个客户端连显示都不允许。
local function ShowValue(fontString, value)
    if not fontString then return false end
    local ok = pcall(fontString.SetText, fontString, value)
    return ok
end

local function HideEntry(entry)
    if not entry then return end
    for _, key in ipairs({ "cur", "sep", "max" }) do
        local fontString = entry[key]
        if fontString then
            pcall(fontString.SetText, fontString, "")
            pcall(fontString.Hide, fontString)
        end
    end
end

local function ShowEntry(entry)
    if not entry then return end
    for _, key in ipairs({ "cur", "sep", "max" }) do
        local fontString = entry[key]
        if fontString then pcall(fontString.Show, fontString) end
    end
end

---现在的框体还能用就返回；看不见了就重新挑一个（换目标、UI 包刚建好自绘框体都会走到这里）。
---重新挑的代价是一次 UIParent 扫描，所以限流 3 秒一次，别让 UNIT_HEALTH 把帧数打爆。
local lastResolve = {}

local function EnsureEntry(unit)
    local entry = entries[unit]

    if entry and IsVisibleChain(entry.frame) then return entry end

    local now = type(GetTime) == "function" and GetTime() or 0
    -- 注意：**即使 entry 为 nil 也必须限流**。之前写成 `if entry and ...`，
    -- 结果「一个框体都没找到」的时候，每次 UNIT_HEALTH 都会重新扫一遍全屏
    -- 再加一次全量帧遍历 —— 战斗中直接把帧数打爆。
    if (now - (lastResolve[unit] or -1000)) < 3 then return entry end
    lastResolve[unit] = now

    local frame, bar = ResolveHost(unit)
    if not frame then return entry end
    if entry and entry.frame == frame and entry.bar == bar then return entry end

    if entry then HideEntry(entry) end
    entries[unit] = nil
    return CreateEntry(unit, frame, bar)
end

--------------------------------------------------------------------------------
-- 自由摆放模式
--
-- 为什么需要它：无限服的目标框是**客户端自己画的**，Lua 里既拿不到那个帧、
-- 它也没有名字（`/qct health scan` 在玩家机器上只列出 TargetFrame，
-- 而玩家真正在看的那个框连名字都没有）。这种情况再怎么扫也贴不上去，
-- 唯一的办法是自己建一个文字框，让玩家拖到血条上 —— 视觉效果一样，
-- 而且换 UI、换分辨率都不会丢。
--------------------------------------------------------------------------------

local floatFrame, floatEntry

local function EnsureFloat()
    if floatFrame then return floatFrame end

    local frame = CreateFrame("Frame", "QuestChainTipHealthText", UIParent)
    frame:SetSize(180, 20)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not self.movableNow then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point and QCT.db then
            QCT.db.healthPos = {
                point = point,
                relPoint = relPoint or point,
                x = x or 0,
                y = y or 0,
            }
        end
        -- 拖一次就自动锁定：一直开着鼠标会挡住下面框体的点击
        if self.movableNow then
            self.movableNow = false
            pcall(self.EnableMouse, self, false)
            QCT:Print("血量数字位置已保存并锁定。想再挪：/qct health move")
        end
    end)

    local pos = QCT.db and QCT.db.healthPos
    if type(pos) == "table" and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        -- 默认放在屏幕上方正中：绝大多数客户端的目标框都在这个位置，
        -- 玩家装上就能看到，再微调一下即可。
        frame:SetPoint("TOP", UIParent, "TOP", 0, -70)
    end

    local fontPath, fontSize, fontFlags = GetFont()
    local function segment(justify, anchor, x)
        local fontString = frame:CreateFontString(nil, "OVERLAY")
        if fontString.SetFont then
            fontString:SetFont(fontPath, math.max(13, (fontSize or 12) + 1), fontFlags)
        end
        if fontString.SetJustifyH then fontString:SetJustifyH(justify) end
        if fontString.SetWidth then fontString:SetWidth(90) end
        fontString:SetTextColor(1, 1, 1)
        if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 1) end
        if fontString.SetShadowOffset then fontString:SetShadowOffset(1, -1) end
        fontString:SetPoint(anchor, frame, "CENTER", x, 0)
        return fontString
    end

    floatEntry = {
        cur = segment("RIGHT", "RIGHT", -8),
        sep = segment("CENTER", "CENTER", 0),
        max = segment("LEFT", "LEFT", 8),
    }
    floatEntry.sep:SetText("/")
    floatEntry.cur:SetText("")
    floatEntry.max:SetText("")

    floatFrame = frame
    return frame
end

---自由模式下的刷新。只跟 target（焦点跟它叠在一起没意义）。
local function UpdateFloat()
    if not (QCT.db and QCT.db.showHealth and QCT.db.healthFloat) then return end
    EnsureFloat()
    local entry = floatEntry
    if not entry then return end

    if not UnitExistsSafe("target") then
        pcall(entry.cur.SetText, entry.cur, "")
        pcall(entry.max.SetText, entry.max, "")
        return
    end

    local cur = NumberOf(UnitHealth, "target")
    local max = NumberOf(UnitHealthMax, "target")
    if cur == nil or max == nil then return end
    ShowValue(entry.cur, cur)
    ShowValue(entry.max, max)
end

---切换到 / 离开自由摆放模式
---@param enabled boolean
function H:SetFloat(enabled)
    enabled = enabled and true or false
    if QCT.db then QCT.db.healthFloat = enabled end

    if enabled then
        -- 关掉「跟随框体」那套，避免两处数字同时出现
        for _, unit in ipairs(UNITS) do
            local old = entries[unit]
            if old then HideEntry(old) end
            entries[unit] = nil
            lastResolve[unit] = nil
        end
        local frame = EnsureFloat()
        pcall(frame.Show, frame)
        -- 切过来就允许拖动，拖一次自动锁定，省得玩家再去找命令
        frame.movableNow = true
        pcall(frame.EnableMouse, frame, true)
        UpdateFloat()
        QCT:Print("血量数值改为自由摆放：|cffffff00按住数字拖动|r，松手自动保存并锁定。")
        QCT:Print("想回到跟随框体：/qct health auto")
    else
        if floatFrame then
            pcall(floatFrame.EnableMouse, floatFrame, false)
            floatFrame.movableNow = false
            if floatEntry then
                pcall(floatEntry.cur.SetText, floatEntry.cur, "")
                pcall(floatEntry.max.SetText, floatEntry.max, "")
            end
            pcall(floatFrame.Hide, floatFrame)
        end
        self:Refresh()
    end
end

---重新允许拖动（拖一次会自动锁定）
function H:ToggleMove()
    if not (QCT.db and QCT.db.healthFloat) then
        QCT:Print("当前不是自由摆放模式。先执行 /qct health float")
        return
    end
    local frame = EnsureFloat()
    frame.movableNow = not frame.movableNow
    pcall(frame.EnableMouse, frame, frame.movableNow)
    if frame.movableNow then
        QCT:Print("现在可以拖动血量数字了，松手自动保存。")
    else
        QCT:Print("已锁定位置。")
    end
end

local function UpdateUnit(unit)
    if not (QCT.db and QCT.db.showHealth) then return end

    -- 自由摆放模式下不碰任何框体，只刷新自己那个文字框
    if QCT.db.healthFloat then
        if unit == "target" then UpdateFloat() end
        return
    end

    local entry = entries[unit]

    if not UnitExistsSafe(unit) then
        if entry then
            pcall(entry.cur.SetText, entry.cur, "")
            pcall(entry.max.SetText, entry.max, "")
        end
        return
    end

    entry = EnsureEntry(unit)
    if not entry then
        -- 一个候选框体都没找到：说一声，否则玩家只会觉得「功能没生效」
        H.announced = H.announced or {}
        local key = unit .. ":noframe"
        if not H.announced[key] then
            H.announced[key] = true
            QCT:Print("没找到可用的", unit, "框体，血量数字无处可挂。用 /qct health scan 看看有哪些框体。")
        end
        return
    end

    local cur = NumberOf(UnitHealth, unit)
    local max = NumberOf(UnitHealthMax, unit)
    if cur == nil or max == nil then return end

    -- 注意：这里绝不能写 string.format("%d / %d", cur, max)。
    -- 血量是 secret value，一格式化就抛错，整个更新静默失败 —— 这正是之前三轮没修好的原因。
    local okCur = ShowValue(entry.cur, cur)
    local okMax = ShowValue(entry.max, max)

    if okCur and okMax then
        if entry.blocked then
            entry.blocked = false
            ShowEntry(entry)
            QCT.Log:Add("health", unit, "血量数值已恢复显示")
        end
        -- 第一次成功显示时播报一次「挂在哪个框体上」。
        -- 玩家装了自绘 UI 时，插件自己挑的框体不一定是玩家真正在看的那个，
        -- 让它在聊天框里说一句，比来回问「数字跑哪去了」高效得多。
        -- 注意这里必须用 H.announced：UpdateUnit 是普通函数、没有 self，
        -- 之前写成 self.announced 会抛「attempt to index a nil value」，
        -- 被外层 pcall 吞掉 —— 数字照常显示，但这一行播报永远不会出现。
        H.announced = H.announced or {}
        if not H.announced[unit] then
            H.announced[unit] = true
            QCT:Print("血量文字已挂到:", FrameName(entry.bar or entry.frame),
                "| 所属框体:", FrameName(entry.frame))
        end
        return
    end

    -- 连 SetText 都不接受：这个客户端不允许插件显示血量。藏起来，只记一次日志，别刷屏。
    if not entry.blocked then
        entry.blocked = true
        HideEntry(entry)
        QCT.Log:Add("health", unit, "客户端拒绝显示血量数值（secret value）")
        QCT:Print("血量数值显示被客户端拒绝（secret value），已隐藏。用 /qct health 看详情。")
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
    self.announced = {}
    for _, unit in ipairs(UNITS) do
        local old = entries[unit]
        if old then HideEntry(old) end
        entries[unit] = nil
        lastResolve[unit] = nil
        -- 自由摆放模式不建「跟随框体」的文字
        if not (QCT.db and QCT.db.healthFloat) then
            local entry = CreateEntry(unit)
            if entry then ShowEntry(entry) end
        end
    end
    if QCT.db and QCT.db.healthFloat then
        local frame = EnsureFloat()
        pcall(frame.Show, frame)
        -- 从设置面板勾上「可拖动」时，直接进入可拖状态并提示一次，
        -- 否则玩家勾完发现拖不动，还得自己去找命令
        if not self.floatHinted then
            self.floatHinted = true
            frame.movableNow = true
            pcall(frame.EnableMouse, frame, true)
            QCT:Print("血量数值为自由摆放：|cffffff00按住数字拖动|r即可移动，松手自动保存并锁定。")
        end
    end
    UpdateAll()
end

---把手动指定的框体挂上去（按名字和按序号两条入口共用）
local function AttachForced(unit, frame)
    -- 手动指定框体就意味着要「跟随框体」，先退出自由摆放
    if QCT.db then QCT.db.healthFloat = false end
    if floatFrame then
        pcall(floatFrame.EnableMouse, floatFrame, false)
        floatFrame.movableNow = false
        if floatEntry then
            pcall(floatEntry.cur.SetText, floatEntry.cur, "")
            pcall(floatEntry.max.SetText, floatEntry.max, "")
        end
        pcall(floatFrame.Hide, floatFrame)
    end

    H.forced = H.forced or {}
    H.forced[unit] = frame
    local old = entries[unit]
    if old then HideEntry(old) end
    entries[unit] = nil
    lastResolve[unit] = nil
    local entry = CreateEntry(unit)
    if entry then ShowEntry(entry) end
    UpdateAll()
end

---手动指定某个单位挂到哪个帧上（`/qct health <帧名>`）。
---自动挑选在自绘 UI 上不一定猜得准，留一个明确的口子，比反复猜快。
---@param unit string
---@param name string
function H:UseFrame(unit, name)
    local frame = _G[name]
    if not frame then return false, "找不到帧: " .. tostring(name) end
    AttachForced(unit, frame)
    return true
end

---`/qct health pick <序号>`：按 `/qct health scan` 列出的序号指定。
---为什么需要它：玩家那个目标框**没有名字**，`/qct health <帧名>` 根本无从下手；
---序号可以直接把「屏幕上你看到的那个」指过来，不需要知道它叫什么。
---@param unit string
---@param index number
function H:UseFrameByIndex(unit, index)
    local list = self.scanList
    if not list or not list[index] then
        return false, "没有第 " .. tostring(index) .. " 项，先执行 /qct health scan"
    end
    local item = list[index]
    AttachForced(unit, item.frame)
    return true, item.name
end

function H:ClearForced()
    self.forced = nil
end

function H:Disable()
    self.enabled = false
    for _, entry in pairs(entries) do
        HideEntry(entry)
        entry.blocked = false
    end
    if floatFrame then
        if floatEntry then
            pcall(floatEntry.cur.SetText, floatEntry.cur, "")
            pcall(floatEntry.max.SetText, floatEntry.max, "")
        end
        pcall(floatFrame.EnableMouse, floatFrame, false)
        floatFrame.movableNow = false
        pcall(floatFrame.Hide, floatFrame)
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
    -- 姓名板会随怪物进出视野不断重建：牌子换了对象，我们挂在上面的文字就跟着没了。
    -- 这两个事件到了就把「重新挑框体」的限流清掉，让下一次血量更新重新挂到新牌子上。
    pcall(frame.RegisterEvent, frame, "NAME_PLATE_UNIT_ADDED")
    pcall(frame.RegisterEvent, frame, "NAME_PLATE_UNIT_REMOVED")
    frame:SetScript("OnEvent", function(_, event, unit)
        if not (QCT.db and QCT.db.showHealth) then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            if unit == "target" or unit == "focus" then
                local ok, err = pcall(UpdateUnit, unit)
                if not ok and QCT.Log then QCT.Log:Add("health", "事件更新失败:", Safe(err)) end
            end
            return
        end
        if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
            for _, key in ipairs(UNITS) do lastResolve[key] = nil end
            UpdateAll()
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

---测试用：自由摆放模式下的三段文字（cur / sep / max）
function H:GetFloatEntry()
    return floatEntry
end

local function SizeOf(frame)
    local w, h = 0, 0
    if type(frame.GetWidth) == "function" then
        local ok, value = pcall(frame.GetWidth, frame)
        if ok and type(value) == "number" then w = value end
    end
    if type(frame.GetHeight) == "function" then
        local ok, value = pcall(frame.GetHeight, frame)
        if ok and type(value) == "number" then h = value end
    end
    return w, h
end

local function PositionOf(frame)
    local left, top = 0, 0
    if type(frame.GetLeft) == "function" then
        local ok, value = pcall(frame.GetLeft, frame)
        if ok and type(value) == "number" then left = value end
    end
    if type(frame.GetTop) == "function" then
        local ok, value = pcall(frame.GetTop, frame)
        if ok and type(value) == "number" then top = value end
    end
    return left, top
end

---`/qct health scan` 用：把所有**看得见的、够大的**框体按屏幕位置列出来。
---
---1.5.22 起**无名帧也列**（走 EnumerateFrames 全量遍历）：
---玩家那个目标框没有名字，旧版只列具名帧，所以列表里只有 TargetFrame 一个，
---根本找不到他要的那个。现在每项带序号，用 /qct health pick <序号> 直接指过去。
function H:Scan()
    QCT:Print("---- 可见框体一览（按屏幕位置排序） ----")

    local list, seen = {}, {}
    local function add(frame)
        if not frame or seen[frame] then return end
        seen[frame] = true
        local name = FrameName(frame)
        -- 整屏容器永远可见、永远最大，列出来只会把真候选挤到后面
        if name == "UIParent" or name == "WorldFrame" then return end
        -- 先看尺寸：绝大多数帧都过不了这一关，比查可见性便宜
        local w, h = SizeOf(frame)
        if w < 60 or h < 18 then return end
        if not IsVisibleChain(frame) then return end
        local left, top = PositionOf(frame)
        list[#list + 1] = {
            frame = frame,
            name = name,
            left = left,
            top = top,
            w = w,
            h = h,
            hasBar = PickHealthBar(frame) ~= nil,
        }
    end

    -- 1) 先在 UIParent 里走一遍（快，覆盖绝大多数界面）
    local function walk(parent, depth)
        if depth > 3 or not parent or type(parent.GetChildren) ~= "function" then return end
        local ok, children = pcall(parent.GetChildren, parent)
        if not ok or type(children) ~= "table" then return end
        for _, child in ipairs(children) do
            add(child)
            walk(child, depth + 1)
        end
    end
    walk(_G.UIParent, 0)

    -- 2) 再全量遍历：无名帧、挂在 WorldFrame 之类下面的帧只能靠这一遍找到
    local full = ForEachFrame(add)

    table.sort(list, function(a, b)
        if math.abs(a.top - b.top) > 5 then return a.top < b.top end
        return a.left < b.left
    end)

    self.scanList = list
    for index, item in ipairs(list) do
        if index > 30 then break end
        QCT:Print("  " .. index .. ". " .. item.name,
            "位置(" .. math.floor(item.left) .. "," .. math.floor(item.top) .. ")",
            "尺寸" .. math.floor(item.w) .. "x" .. math.floor(item.h),
            item.hasBar and "[有血条]" or "")
    end
    if #list == 0 then
        QCT:Print("  一个都没找到。")
    end
    if not full then
        QCT:Print("  （这个客户端没有 EnumerateFrames，只能扫到 UIParent 里的具名帧）")
    end
    QCT:Print("共", #list, "个。找到目标框后：/qct health pick <序号> 指定；/qct health reset 恢复自动")
    QCT:Print("如果它确实贴不上去：/qct health float 改成可拖动的数字，拖到血条上即可。")
end

---`/qct health` 用：把「框体找没找到 / 血条找没找到 / 文字状态」全打出来。
---玩家反馈「血量不显示」时，光看代码猜不出来，得看实际结构。
---整段包 pcall：这个客户端上随便哪个返回值是 secret value，诊断本身就会先炸，
---上一版就是这样 —— 只打出「开关: true」两行，后面的全没了，等于没诊断。
function H:Diagnose()
    QCT:Print("---- 血量诊断 ----")
    QCT:Print("开关:", Safe(QCT.db and QCT.db.showHealth),
        "| 自由摆放:", Safe(QCT.db and QCT.db.healthFloat))

    for _, unit in ipairs(UNITS) do
        local ok, err = pcall(function()
            local exists = UnitExistsSafe(unit)
            local cur = NumberOf(UnitHealth, unit)
            local max = NumberOf(UnitHealthMax, unit)

            QCT:Print(unit, "| 单位存在:", Safe(exists),
                "| 血量:", Safe(cur), "/", Safe(max))

            -- 关键：分清「读得到」和「能显示」。
            -- 这个客户端上血量读得到（tonumber 不报错），但一格式化就抛 secret，
            -- 所以必须分别探一次，否则永远不知道卡在哪一步。
            local formatOk = pcall(string.format, "%d / %d", cur or 0, max or 0)
            QCT:Print("  能格式化成字符串:", Safe(formatOk))

            -- 单独探一次 SetText：如果连这个都不接受，那就真的没法显示，
            -- 跟框体/层级无关，不用再猜了。用一个临时 FontString，不动真实文字。
            local setTextOk = pcall(function()
                local probe = _G.UIParent:CreateFontString(nil, "OVERLAY")
                local ok = pcall(probe.SetText, probe, cur)
                pcall(probe.SetText, probe, "")
                pcall(probe.Hide, probe)
                return ok
            end)
            QCT:Print("  能直接 SetText 原始血量:", Safe(setTextOk))

            local entry = entries[unit]
            if entry then
                local tok, text = pcall(entry.cur.GetText, entry.cur)
                QCT:Print("  文字:", tok and Safe(text) or "<读不到>",
                    "| 可见:", Safe(IsVisibleChain(entry.cur)),
                    "| 挂在:", FrameName(entry.bar or entry.frame),
                    "| 被客户端拒绝:", Safe(entry.blocked))
            else
                QCT:Print("  文字: 还没创建")
            end

            -- 候选框体一览：玩家装了自绘 UI 时，看这一行就知道该往哪儿挂。
            -- 带上屏幕坐标：一个单位常常有好几个框体同时可见（暴雪默认的 + UI 包的），
            -- 光看名字分不清哪个是玩家真正在看的，坐标一看就知道。
            local candidates = Candidates(unit)
            local parts = {}
            for i, frame in ipairs(candidates) do
                if i > 6 then break end
                local bar = PickHealthBar(frame)
                local left, top = 0, 0
                if type(frame.GetLeft) == "function" then
                    local ok, value = pcall(frame.GetLeft, frame)
                    if ok and type(value) == "number" then left = value end
                end
                if type(frame.GetTop) == "function" then
                    local ok, value = pcall(frame.GetTop, frame)
                    if ok and type(value) == "number" then top = value end
                end
                parts[#parts + 1] = FrameName(frame)
                    .. (IsVisibleChain(frame) and "[显示]" or "[隐藏]")
                    .. "(" .. math.floor(left) .. "," .. math.floor(top) .. ")"
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
