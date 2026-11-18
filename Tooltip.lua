--[[
展示层：不往 Blizzard 的 GameTooltip 里追加行（会被撑高→被系统上挤→盖住鼠标→提示反复隐藏/弹出＝闪烁），
也不用 GameTooltip 模板（部分客户端上模板帧会被 tooltip 自身逻辑隐藏）。
这里是一个完全自绘的普通 Frame：背景 + 边框 + 每行左右两个 FontString，位置和显隐完全由我们控制。
]]

local ADDON, ns = ...
local QCT = ns
local F = QCT.Format
local D = QCT.Data
local L = QCT.Locale

local T = {}
QCT.Tooltip = T

local PANEL_NAME = "QuestChainTipPanel"
local TEXT_WIDTH = 330      -- 文本列宽
local PAD_X, PAD_Y = 10, 8
local LINE_HEIGHT = 15
local MAX_ROWS = 42

--------------------------------------------------------------------------------
-- 详情窗快捷键
--
-- 原来写死 Shift，但 Questie 自己也用 Shift（地图上按住 Shift 切换被隐藏的任务标记），
-- 两边撞在一起：玩家想切 Questie 的隐藏任务，我们这边却弹了个窗。
-- 现在让玩家在设置里选 Shift / Ctrl / Alt / 不启用，默认仍是 Shift（老用户零感知）。
--
-- 这段必须放在文件靠前的位置：下面 Update() 里拼提示文案要用 ChainKeyLabel()，
-- 而 Lua 的 local 作用域从声明处才开始，放到后面会被当成全局变量（nil）。
--------------------------------------------------------------------------------

local CHAIN_KEY_ORDER = { "SHIFT", "CTRL", "ALT", "NONE" }
local MODIFIER_SET = { SHIFT = true, CTRL = true, ALT = true }

---当前生效的快捷键。可以是 SHIFT / CTRL / ALT / NONE，也可以是任意按键串（"F"、"CTRL-1"）。
local function ChainKey()
    local key = QCT.db and QCT.db.chainKey
    if type(key) == "string" and key ~= "" then return key end
    return "SHIFT"
end
T.ChainKey = ChainKey

---是不是三个修饰键之一（这三个走事件监听，其它键走游戏绑定）
local function IsModifierKey(key)
    return MODIFIER_SET[key] == true
end
T.IsModifierKey = IsModifierKey

---快捷键显示名。Shift/Ctrl/Alt 是英文键名，各语言都不译；「不启用」才需要翻译。
local function ChainKeyLabel()
    local key = ChainKey()
    if key == "NONE" then return L["不启用"] end
    if IsModifierKey(key) then return key:sub(1, 1) .. key:sub(2):lower() end
    return key
end
T.ChainKeyLabel = ChainKeyLabel

---某个全局按键函数现在是不是按下状态。客户端没有这个 API 就当作没按。
local function KeyDown(globalName)
    local fn = _G[globalName]
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn)
    return ok and value and true or false
end

---配置的那个快捷键现在按着没有
local function IsChainKeyDown()
    local key = ChainKey()
    if key == "NONE" then return false end
    if key == "CTRL" then return KeyDown("IsControlKeyDown") end
    if key == "ALT" then return KeyDown("IsAltKeyDown") end
    return KeyDown("IsShiftKeyDown")
end
T.IsChainKeyDown = IsChainKeyDown

---把 MODIFIER_STATE_CHANGED 的按键名（LSHIFT / RSHIFT / LCTRL / RCTRL / LALT / RALT）
---归到 SHIFT / CTRL / ALT 三族，方便和配置值直接比。
local function KeyFamily(key)
    if type(key) ~= "string" then return nil end
    if key:find("SHIFT", 1, true) then return "SHIFT" end
    if key:find("CTRL", 1, true) then return "CTRL" end
    if key:find("ALT", 1, true) then return "ALT" end
    return nil
end
T.KeyFamily = KeyFamily
T.ChainKeyOrder = CHAIN_KEY_ORDER

--------------------------------------------------------------------------------
-- 自定义快捷键：任意键
--
-- 修饰键靠 MODIFIER_STATE_CHANGED，零副作用。但玩家想绑 F / 数字键这类，
-- 事件监听做不到——WoW 没有通用的「某个键现在按着吗」API，
-- 只能用 SetBindingClick 把按键绑到一个隐藏按钮上。
-- 代价：会占用那个键原本的绑定（玩家自己选的，设置界面有提示）。
--------------------------------------------------------------------------------

local HOTKEY_BUTTON = "QuestChainTipHotkeyButton"
local boundKey = nil

local function HotkeyButton()
    local button = _G[HOTKEY_BUTTON]
    if button then return button end
    button = CreateFrame("Button", HOTKEY_BUTTON, UIParent)
    button:SetSize(1, 1)
    button:Hide()
    button:SetScript("OnClick", function()
        if T.TryOpenFromHover then pcall(T.TryOpenFromHover, T, "hotkey") end
    end)
    return button
end

---把配置的按键重新应用到游戏绑定上。改成修饰键 / 不启用时先把旧绑定清掉。
---@return boolean 是否成功（修饰键模式恒为 true）
function T:ApplyChainKey()
    if boundKey then
        if type(SetBindingClick) == "function" then
            pcall(SetBindingClick, boundKey)
        elseif type(SetBinding) == "function" then
            pcall(SetBinding, boundKey)
        end
        boundKey = nil
    end

    local key = ChainKey()
    if IsModifierKey(key) or key == "NONE" then return true end

    HotkeyButton()
    local ok = false
    if type(SetBindingClick) == "function" then
        ok = pcall(SetBindingClick, key, HOTKEY_BUTTON)
    elseif type(SetBinding) == "function" then
        ok = pcall(SetBinding, key, "CLICK " .. HOTKEY_BUTTON)
    end
    if ok then
        boundKey = key
        if type(SaveBindings) == "function" then pcall(SaveBindings, 2) end
    end
    return ok and true or false
end

local NEXT_ICON = "|TInterface\\AddOns\\Questie\\Icons\\nextquest.blp:14:14:0:0|t"
local REP_ICON = "|TInterface\\AddOns\\Questie\\Icons\\reputation.blp:14:14:0:0|t"

local INDENT = "   "

local STATE_TEXT = {
    active = { text = L["(进行中)"], r = 1.00, g = 0.82, b = 0.00 },
    completed = { text = L["(已完成)"], r = 0.55, g = 0.55, b = 0.55 },
    available = { text = L["(可接)"], r = 0.25, g = 1.00, b = 0.25 },
    locked = { text = L["(条件不足)"], r = 0.90, g = 0.40, b = 0.40 },
    unknown = { text = L["(未知)"], r = 0.60, g = 0.60, b = 0.60 },
}

--------------------------------------------------------------------------------
-- 小工具
--------------------------------------------------------------------------------

local function GetTipFontString(tip, index, side)
    local name = tip:GetName()
    if not name then return nil end
    return _G[name .. (side == "right" and "TextRight" or "TextLeft") .. index]
end

local function StateText(questId)
    local state = D:GetState(questId)
    local info = STATE_TEXT[state] or STATE_TEXT.unknown
    return F.Hex(info.r, info.g, info.b, info.text)
end

---"[38] 任务名"，颜色按难度
local function QuestTitle(questId)
    local mod = D.mod
    if mod.QuestieLib and type(mod.QuestieLib.GetColoredQuestName) == "function" then
        local ok, text = pcall(mod.QuestieLib.GetColoredQuestName, mod.QuestieLib, questId, true, false)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end
    local name = D:GetName(questId) or L.F("任务 %s", tostring(questId))
    local level = D:GetLevel(questId)
    local prefix = (level and level > 0) and ("[" .. level .. "] ") or ""
    return F.DifficultyText(level, questId, prefix .. name)
end

---"(3,900经验) (1金币)"
local function RewardShort(questId)
    local parts = {}
    local xp = D:GetXP(questId)
    if xp > 0 then
        local r, g, b = F.DifficultyColor(D:GetLevel(questId), questId)
        parts[#parts + 1] = F.Hex(r, g, b, "(" .. F.Number(xp) .. L["经验"] .. ")")
    end
    local money = D:GetMoney(questId)
    if money > 0 then
        parts[#parts + 1] = "(" .. F.Coins(money) .. ")"
    end
    return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- 面板（纯自绘）
--------------------------------------------------------------------------------

local fontPath, fontSize, fontFlags

local function GetFont()
    -- 不缓存：玩家换字体/改字号后不用重载插件也能跟上
    local source = _G["GameTooltipTextLeft1"]
    if source and source.GetFont then
        local ok, path, size, flags = pcall(source.GetFont, source)
        if ok and path and size then
            fontPath, fontSize, fontFlags = path, size, flags or ""
            return fontPath, fontSize, fontFlags
        end
    end
    fontPath, fontSize, fontFlags = "Fonts\\ARKai_T.ttf", 12, ""
    return fontPath, fontSize, fontFlags
end

function T:CreatePanel()
    if self.panel then return self.panel end

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local panel = CreateFrame("Frame", PANEL_NAME, UIParent, template)
    panel:SetSize(TEXT_WIDTH + PAD_X * 2, 80)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetFrameLevel(500)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(false)

    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        panel:SetBackdropColor(0, 0, 0, 0.92)
        panel:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    else
        local background = panel:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        background:SetAllPoints()
        background:SetVertexColor(0, 0, 0, 0.92)
    end

    panel.rows = {}
    panel:Hide()

    self.panel = panel
    return panel
end

---把面板的底色和边框色对齐 GameTooltip。
---为什么：面板和任务图标提示是上下紧挨着显示的两个框，底色/边框只要有一点不一样，
---看起来就是「两个软件拼在一起」。原生 tooltip 的样式还会被 ElvUI / Tiptac 这类美化改掉，
---所以这里每次都现读一次，不做缓存。
function T:SyncPanelStyle()
    local panel = self.panel
    local tip = _G.GameTooltip
    if not panel or not tip then return end

    if panel.SetBackdropColor and tip.GetBackdropColor then
        local ok, r, g, b, a = pcall(tip.GetBackdropColor, tip)
        -- 有的美化插件把 GameTooltip 设成全透明（反正它不用这个框），
        -- 盲目跟随会让我们也变透明，低于 0.3 就保留默认值
        if ok and r and a and a >= 0.3 then
            panel:SetBackdropColor(r, g, b, a)
        end
    end

    if panel.SetBackdropBorderColor and tip.GetBackdropBorderColor then
        local ok, r, g, b, a = pcall(tip.GetBackdropBorderColor, tip)
        if ok and r then
            panel:SetBackdropBorderColor(r, g, b, a or 1)
        end
    end
end

-- 安全调用：某些客户端（或测试桩）缺少个别 FontString 方法，不能因此整个面板炸掉
local function SafeCall(obj, method, ...)
    local fn = obj and obj[method]
    if fn then return fn(obj, ...) end
end

local function AcquireRow(panel, index)
    local row = panel.rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, panel)

    local path, size, flags = GetFont()
    row.left = row:CreateFontString(nil, "ARTWORK")
    SafeCall(row.left, "SetFont", path, size, flags)
    SafeCall(row.left, "SetJustifyH", "LEFT")
    SafeCall(row.left, "SetJustifyV", "TOP")
    SafeCall(row.left, "SetWordWrap", true)
    -- 原生 tooltip 的文字带 1px 黑影。不加阴影的话同样的字号看着更粗更亮，
    -- 和上面的任务提示放在一起对比很明显。
    SafeCall(row.left, "SetShadowColor", 0, 0, 0, 1)
    SafeCall(row.left, "SetShadowOffset", 1, -1)

    row.right = row:CreateFontString(nil, "ARTWORK")
    SafeCall(row.right, "SetFont", path, size, flags)
    SafeCall(row.right, "SetJustifyH", "RIGHT")
    SafeCall(row.right, "SetJustifyV", "TOP")
    SafeCall(row.right, "SetWordWrap", false)
    SafeCall(row.right, "SetShadowColor", 0, 0, 0, 1)
    SafeCall(row.right, "SetShadowOffset", 1, -1)

    panel.rows[index] = row
    return row
end

---把内容行排进面板，并算出面板高度
---@param content table[] 每项 { left = string, right = string?, r,g,b }
function T:Layout(content)
    local panel = self.panel
    local y = -PAD_Y
    local count = #content

    for index = 1, count do
        local item = content[index]
        local row = AcquireRow(panel, index)

        row:Show()

        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, y)
        row.left:SetTextColor(item.r or 1, item.g or 1, item.b or 1)
        row.left:SetText(item.left or "")

        local rightWidth = 0
        if item.right and item.right ~= "" then
            row.right:SetTextColor(item.r or 1, item.g or 1, item.b or 1)
            row.right:SetText(item.right)
            row.right:Show()
            rightWidth = row.right:GetStringWidth() or 0
        else
            row.right:SetText("")
            row.right:Hide()
        end

        -- 先按满宽量一次，拿到「不换行时左边这行要多宽」。
        -- 之前直接把左边挤到 TEXT_WIDTH - rightWidth，任务名一长就被切成两行：
        -- 最后一个字掉到下一行，又被面板高度裁掉，看着像排版错乱
        -- （比如「抢救数据」显示成「抢救数」，底边框外露出一个「据」）。
        row.left:SetWidth(TEXT_WIDTH)
        local natural = row.left:GetStringWidth() or 0
        local stacked = rightWidth > 0 and (natural + rightWidth + 6) > TEXT_WIDTH

        local height
        if stacked then
            -- 一行放不下：任务名独占一行，右侧信息降到下一行右对齐
            local h1 = row.left:GetStringHeight() or 0
            if h1 <= 0 then h1 = LINE_HEIGHT end

            row.right:ClearAllPoints()
            row.right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD_X, y - h1)

            local h2 = row.right:GetStringHeight() or 0
            if h2 <= 0 then h2 = LINE_HEIGHT end
            height = h1 + h2
        else
            local leftWidth = TEXT_WIDTH - rightWidth - 6
            if leftWidth < 60 then leftWidth = 60 end
            row.left:SetWidth(leftWidth)

            if rightWidth > 0 then
                row.right:ClearAllPoints()
                row.right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD_X, y)
            end

            height = row.left:GetStringHeight() or 0
            if height <= 0 then height = LINE_HEIGHT end
        end

        -- GetStringHeight 不含字体下沿的行距，逐行累加会让面板底部越来越贴边
        -- （顶部留 10px、底部只剩 2~3px，最后一行几乎压住边框）。每行补 1px。
        y = y - height - 1
    end

    -- 收起多余的行
    for index = count + 1, #panel.rows do
        local row = panel.rows[index]
        row.left:SetText("")
        row.right:SetText("")
        row:Hide()
    end

    panel:SetWidth(TEXT_WIDTH + PAD_X * 2)
    -- 底部多留 3px：行高累加本身有细微误差，且底边框的下沿需要呼吸空间
    panel:SetHeight(math.max(40, -y + PAD_Y + 3))
end

---把面板放在 GameTooltip 旁边：优先下方，其次右侧、左侧，最后居中。
function T:PlacePanel()
    local panel = self.panel
    if not panel then return end

    panel:ClearAllPoints()

    local screenWidth = UIParent:GetWidth() or 1920
    local panelWidth = panel:GetWidth() or 0
    local panelHeight = panel:GetHeight() or 0
    local tipLeft = GameTooltip:GetLeft()
    local tipRight = GameTooltip:GetRight()
    local tipBottom = GameTooltip:GetBottom()

    if tipBottom and (tipBottom - panelHeight - 6) >= 0 then
        panel:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -4)
        return
    end
    if tipRight and (tipRight + panelWidth + 6) <= screenWidth then
        panel:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 4, 0)
        return
    end
    if tipLeft and (tipLeft - panelWidth - 6) >= 0 then
        panel:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", -4, 0)
        return
    end
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

--------------------------------------------------------------------------------
-- 内容
--------------------------------------------------------------------------------

function T:Hide()
    self.builtQuestId = nil
    self.builtShift = nil
    if self.panel and self.panel:IsShown() then
        self.panel:Hide()
    end
end

---按当前状态重建面板内容
function T:Update(questId)
    if not QCT.db.enabled then
        self:Hide()
        return
    end
    if not questId then
        self:Hide()
        return
    end
    if not D:GetQuest(questId) then
        self:Hide()
        if not D.available and not self.warnedNoData then
            self.warnedNoData = true
            QCT:Print(L["没有读到 Questie 的任务数据（请确认 Questie 已启用）。输入 |cffffff00/qct why|r 查看详情。"])
        end
        QCT:Debug("任务", tostring(questId), "拿不到任何数据（Questie 未就绪且客户端也查不到），面板隐藏")
        return
    end

    -- 详情窗只在地图上用 Shift 触发：地图上 Shift 没有被游戏占用，
    -- 而任务日志里 Shift+点击是原生的「把任务链接贴到聊天框」，不能抢。

    local ok, err = pcall(self.Build, self, questId)
    if not ok then
        self:Hide()
        self.lastError = tostring(err)
        QCT.Log:Add("error", "渲染失败:", tostring(err))
        -- 同一个错误只提示一次，避免刷屏
        if self.lastPrintedError ~= self.lastError then
            self.lastPrintedError = self.lastError
            QCT:Print(L.F("面板渲染出错：%s", tostring(err)))
        end
        return
    end
    self.lastError = nil
end

function T:Build(questId)
    local panel = self:CreatePanel()
    self:SyncPanelStyle()
    local db = QCT.db
    -- 行内面板始终按普通深度渲染
    local shift = false

    local content = {}
    local function addLine(text, r, g, b)
        if #content >= MAX_ROWS then return end
        content[#content + 1] = { left = text, r = r or 1, g = g or 1, b = b or 1 }
    end
    local function addDouble(left, right, r, g, b)
        if #content >= MAX_ROWS then return end
        content[#content + 1] = { left = left, right = right, r = r or 1, g = g or 1, b = b or 1 }
    end
    local function addHeader(text)
        addLine(F.DIM .. text .. "|r")
    end

    -- 每个区块单独保护：某一段取数据出错只丢这一段，不至于整块面板消失
    local function section(name, fn)
        local ok, err = pcall(fn)
        if not ok then
            QCT.Log:Add("build", "区块出错:", name, "|", tostring(err))
        end
        return ok
    end

    -- 抬头：等级/难度着色 + 当前状态
    section("标题", function()
        addDouble(QuestTitle(questId), StateText(questId))
    end)

    local hasContent = false

    -- 任务描述
    section("描述", function()
        if not db.showDescription then return end
        local desc = D:GetDescription(questId)
        if #desc == 0 then return end

        addHeader(L["任务描述"])
        local maxLines = shift and 30 or db.descLines
        local used = 0
        local truncated = false
        for _, paragraph in ipairs(desc) do
            if used >= maxLines then truncated = true break end
            for _, wrapped in ipairs(F.Wrap(paragraph, INDENT, TEXT_WIDTH - 10, nil)) do
                if used >= maxLines then truncated = true break end
                addLine(wrapped, 0.86, 0.86, 0.86)
                used = used + 1
            end
        end
        if truncated then
            addLine(F.DIM .. INDENT .. L.F("…（在世界地图上按住 %s 查看完整任务链）", ChainKeyLabel()) .. "|r")
        end
        hasContent = true
    end)

    -- 任务奖励
    section("奖励", function()
        if not db.showRewards then return end

        local xp = D:GetXP(questId)
        local money = D:GetMoney(questId)
        local items = D:GetRewardItems(questId)
        local reputations = D:GetReputationReward(questId)

        if not (xp > 0 or money > 0 or #items > 0 or #reputations > 0) then return end

        addHeader(L["任务奖励"])

        local parts = {}
        if xp > 0 then
            local r, g, b = F.DifficultyColor(D:GetLevel(questId), questId)
            parts[#parts + 1] = F.Hex(r, g, b, F.Number(xp) .. L["经验"])
        end
        if money > 0 then
            parts[#parts + 1] = F.Coins(money)
        end
        if #parts > 0 then
            addLine(INDENT .. table.concat(parts, "   "), 1, 1, 1)
        end

        if #items > 0 then
            local texts = {}
            for _, item in ipairs(items) do
                texts[#texts + 1] = item.text
            end
            addLine(INDENT .. table.concat(texts, "  "), 1, 1, 1)
        end

        for _, rep in ipairs(reputations) do
            local text = (rep.value > 0 and "+" or "") .. rep.value .. " " .. rep.faction
            addLine(INDENT .. REP_ICON .. " " .. F.Hex(0.35, 0.55, 1, text), 1, 1, 1)
        end

        hasContent = true
    end)

    -- 后续任务链
    section("后续任务链", function()
        if not db.showChain then return end

        local depth = shift and db.chainDepthShift or db.chainDepth
        local chain, truncated = D:BuildChain(questId, depth)
        if #chain == 0 then return end

        addHeader(NEXT_ICON .. " " .. L["后续任务"])
        for _, nextId in ipairs(chain) do
            local right = ""
            if db.chainRewards then
                right = RewardShort(nextId)
                if right ~= "" then right = right .. " " end
            end
            addDouble(INDENT .. QuestTitle(nextId), right .. StateText(nextId))
        end
        if truncated and not shift then
            addLine(F.DIM .. INDENT .. L.F("…（在世界地图上按住 %s 查看完整任务链）", ChainKeyLabel()) .. "|r")
        end
        hasContent = true
    end)

    -- 前置任务
    section("前置任务", function()
        if not db.showPrereq then return end

        local prereqs = D:BuildPrerequisiteChain(questId, 1)
        if #prereqs == 0 then return end

        addHeader(L["前置任务"])
        for _, preId in ipairs(prereqs) do
            addDouble(INDENT .. QuestTitle(preId), StateText(preId))
        end
    end)

    if not hasContent then
        panel:Hide()
        return
    end

    self:Layout(content)
    self:PlacePanel()
    panel:Show()

    self.builtQuestId = questId
    self.builtShift = shift

    QCT.Log:Add("panel", "构建完成 | 任务:", questId, "| Shift:", shift and "是" or "否",
        "| 行数:", #content, "| 尺寸:", tostring(panel:GetWidth()) .. "x" .. tostring(panel:GetHeight()),
        "| 显示:", panel:IsShown() and "是" or "否")
end

--------------------------------------------------------------------------------
-- 识别
--------------------------------------------------------------------------------

---安全读取帧上的一个数字字段（只接受正数，其它一律当没有）
local function SafeNumber(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok and type(value) == "number" and value > 0 then return value end
    return nil
end

---安全调用无参方法取数字
local function SafeMethodNumber(object, method)
    local fn = object and object[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object)
    if ok and type(value) == "number" and value > 0 then return value end
    return nil
end

local function SafeName(object)
    local ok, value = pcall(function() return object:GetName() end)
    if ok and type(value) == "string" then return value end
    return nil
end

---判断这个帧是不是任务日志里的一行。
---注意：任务日志可能嵌在世界地图右边（地图打开时的任务列表），所以必须逐层往上找，
---不能只看直接父级——否则「地图上的任务日志」会被当成地图图标。
local function IsQuestLogButton(owner, name)
    local frame = owner
    for _ = 1, 6 do
        if not frame then break end
        local frameName = (frame == owner) and name or SafeName(frame)
        -- 名字里带 QuestLog 的一律算任务日志（QuestLogTitle1、QuestLogFrame、
        -- 以及地图上那个 WorldMapQuestLogScrollFrame 都覆盖到了）
        if frameName and frameName:find("QuestLog", 1, true) then
            return true
        end
        if frame == _G.QuestLogFrame or frame == _G.QuestLogListScrollFrame then return true end
        local ok, parent = pcall(function() return frame:GetParent() end)
        frame = ok and parent or nil
    end
    return false
end

---判断这个帧是不是聊天框（含向上找几层父级）。
---聊天框里悬停任务链接时不该弹我们的面板：玩家在那里是要复制/点击链接，
---面板一出来就挡住聊天内容，还容易让人点错。
local function IsChatFrame(owner)
    if not owner then return false end
    local frame = owner
    for _ = 1, 4 do
        if not frame then break end
        local name = SafeName(frame)
        if name and (name:match("^ChatFrame%d*$") or name:match("^ChatFrame%d+Tab$")
            or name:match("^ChatFrame%d+EditBox$")) then
            return true
        end
        local ok, parent = pcall(function() return frame:GetParent() end)
        frame = ok and parent or nil
    end
    return false
end
T.IsChatFrame = IsChatFrame

---判断这个帧是不是在世界地图上（Questie 的地图任务图标都挂在地图帧下面）。
---悬停面板默认只在世界地图上出现：任务日志、聊天框里弹面板会挡住玩家要点/要复制的东西。
local function IsOnWorldMap(owner)
    if not owner then return false end
    local map = _G.WorldMapFrame
    local frame = owner
    for _ = 1, 8 do
        if not frame then break end
        if map and frame == map then return true end
        local name = SafeName(frame)
        if name and name:match("^WorldMap") then return true end
        local ok, parent = pcall(function() return frame:GetParent() end)
        frame = ok and parent or nil
    end
    return false
end
T.IsOnWorldMap = IsOnWorldMap

---这个帧是不是挂在「世界地图的画布」里，而不是地图旁边的任务列表里。
---
---这个区分必须做，因为两者结构几乎一样（都是无名 Button 套在无名 ScrollFrame 里）：
---  地图标记:  <无名>(Button) > <无名>(Frame) > <无名>(ScrollFrame) > WorldMapFrame
---  列表行:    <无名>(Button) > <无名>(ScrollFrame) > <某个列表面板> > WorldMapFrame
---唯一稳定的差别是：**地图画布那个 ScrollFrame 的父级直接就是 WorldMapFrame**，
---而列表的滚动帧挂在一个面板下面。所以走到第一个 ScrollFrame 时看它的父级就够了。
local function IsOnMapCanvas(owner)
    local map = _G.WorldMapFrame
    if not map then return true end

    -- 能拿到画布就更好：祖先链里出现画布直接算地图
    local canvas
    local cok, cvalue = pcall(function() return map:GetCanvas() end)
    if cok then canvas = cvalue end

    local frame = owner
    for _ = 1, 6 do
        if not frame then break end
        if canvas and frame == canvas then return true end

        local ok, kind = pcall(function() return frame:GetObjectType() end)
        if ok and kind == "ScrollFrame" then
            local pok, parent = pcall(function() return frame:GetParent() end)
            if not pok then return true end          -- 判断不了就别拦，宁可多弹
            return parent == nil or parent == map
        end

        local pok, parent = pcall(function() return frame:GetParent() end)
        frame = pok and parent or nil
    end

    -- 祖先链里压根没有滚动帧：直接挂在画布上的标记，算地图
    return true
end
T.IsOnMapCanvas = IsOnMapCanvas

---世界地图是不是开着。Questie 自己也用 WorldMapFrame:IsShown() 区分地图/小地图。
local function IsWorldMapOpen()
    local map = _G.WorldMapFrame
    if not map or type(map.IsShown) ~= "function" then return false end
    local ok, shown = pcall(map.IsShown, map)
    return ok and shown == true
end
T.IsWorldMapOpen = IsWorldMapOpen

---Questie 图标的三态判定："map"（世界地图图标）/ "minimap"（小地图图标）/ nil（不是 Questie 图标）。
---
---判定依据全部来自 Questie 源码，不靠父级去猜：
---  * 帧名是 QuestieFrame<id>：Modules/FramePool/QuestieFrame.lua:59
---    `local newFrame = CreateFrame("Button", "QuestieFrame" .. frameId)`
---  * 图标数据挂在 .data 上，任务 ID 就是 .data.Id（Modules/Tooltips/MapIconTooltip.lua）
---  * 地图图标 .miniMapIcon = false，小地图图标 .miniMapIcon = true：
---    Modules/Map/QuestieMap.lua:565 / 590 / 675 / 687
---
---为什么不能用「父级是不是地图帧」来判断：地图图标会被 HereBeDragons 重新挂到
---WorldMapFrame 的画布下（Libs/HereBeDragons/HereBeDragons-Pins-2.0.lua:503 icon:SetParent(self)，
---画布是 WorldMapFrame:GetCanvas()），小地图图标则挂到 Minimap 下（同文件 :616）。
---父级链在别的任务插件那里完全可能不同，而 miniMapIcon 是 Questie 自己写死的字段，最可靠。
local function QuestieIconKind(owner)
    if not owner then return nil end

    local name = SafeName(owner)
    local named = name ~= nil and name:match("^QuestieFrame%d+$") ~= nil

    local dataOk, data = pcall(function() return owner.data end)
    local dataId = nil
    if dataOk and type(data) == "table" then
        for _, key in ipairs({ "Id", "id", "questId", "questID" }) do
            dataId = SafeNumber(data, key)
            if dataId then break end
        end
    end

    if not named and not dataId then return nil end

    local miniOk, mini = pcall(function() return owner.miniMapIcon end)
    if miniOk and mini == true then return "minimap" end
    return "map"
end
T.QuestieIconKind = QuestieIconKind

---当前提示框的持有者（谁把提示弹出来的）。
---绝对不能只信 SetOwner 钩子记下来的值：这个客户端上 C 函数不一定钩得住，
---钩子一旦没装上，self.owner 就永远是 nil，整套判定（地图图标/任务日志/聊天框）全部跟着失效，
---表现出来就是「怎么按 Shift 都不弹，也不报错」。
---所以每次都直接问 GameTooltip 要，钩子记的值只当最后的兜底。
---@param tip table? 默认 GameTooltip
---@return table? owner
local function CurrentOwner(tip)
    tip = tip or _G.GameTooltip
    if not tip then return nil end

    local ok, owner = pcall(function() return tip:GetOwner() end)
    if ok and owner then return owner end

    -- 只有 GetOwner() 完全拿不到时才看 _owner。
    -- 注意：Questie 的 _owner 是**上一次**悬停地图图标时留下的，不会清空，
    -- 所以它绝不能优先于 GetOwner()——否则从地图图标挪到聊天框、任务日志之后，
    -- 拿到的还是那个旧图标，聊天框里也会被当成地图图标弹窗。
    local ok2, fallback = pcall(function() return tip._owner end)
    if ok2 and fallback then return fallback end

    return T.owner
end
T.CurrentOwner = CurrentOwner

---Questie 图标上挂的数据是不是「任务」。
---地图上还有一类图标是 NPC/物件的标注（Modules/Map/QuestieMap.lua:400/475 data.Type = "manual"），
---它们的 data.Id 是 NPC 编号不是任务 ID，拿它去开任务详情窗只会弹出一个空窗。
local function IsQuestIconData(owner)
    local ok, data = pcall(function() return owner.data end)
    if not ok or type(data) ~= "table" then return true end
    local tok, kind = pcall(function() return data.Type end)
    if tok and kind == "manual" then return false end
    return true
end

---是不是「地图上真正的任务图标」。
---要排除三种会误伤的情况：
---  1) 小地图图标（小地图上 Shift 没意义，而且小地图一直开着，会一直弹）
---  2) 地图上的 NPC/物件标注（不是任务，没有任务详情可看）
---  3) 任务日志的行（含世界地图右侧那个任务列表）：Shift+点击是游戏原生的
---     「把任务链接贴到聊天框」，抢了玩家就没法复制任务链接了。
---
---反过来，**只要确实在世界地图里就算**。这条不能加别的条件：
---这个客户端的世界地图任务标记是暴雪自己的无名 Button，祖先链是
---`<无名>(Button) > <无名>(Frame) > <无名>(ScrollFrame) > WorldMapFrame`，
---既没有 QuestieFrame 的名字，也没有任务 ID 字段，任何「要有正面证据」的额外条件都会把它排掉。
local function IsMapQuestIcon(owner)
    if not owner then return false end
    if IsQuestLogButton(owner) then return false end
    if IsChatFrame(owner) then return false end

    local kind = QuestieIconKind(owner)
    if kind then
        -- Questie 的图标：miniMapIcon 一眼就能分开地图和小地图，不用看父级
        if kind ~= "map" then return false end
        return IsQuestIconData(owner)
    end

    -- 暴雪自己 / 其他任务插件的地图标记：挂在地图帧里、而且是在地图画布里（不是旁边的任务列表）
    return IsOnWorldMap(owner) and IsOnMapCanvas(owner)
end
T.IsMapQuestIcon = IsMapQuestIcon

---把帧的祖先链描述出来，排查「这个提示到底是谁弹的」用
function T:DescribeFrameChain(owner)
    local parts = {}
    local frame = owner
    for _ = 1, 6 do
        if not frame then break end
        local name = SafeName(frame) or "<无名>"
        local kind = "?"
        local ok, value = pcall(function() return frame:GetObjectType() end)
        if ok and type(value) == "string" then kind = value end
        local id = SafeMethodNumber(frame, "GetID")
        parts[#parts + 1] = name .. "(" .. kind .. (id and (":" .. id) or "") .. ")"
        local pok, parent = pcall(function() return frame:GetParent() end)
        frame = pok and parent or nil
    end
    return table.concat(parts, " > ")
end

---只从帧字段里拿任务 ID，绝不读提示文本。
---这个客户端的 tooltip 文本对插件是 secret value，读出来一比较就抛错，
---但数字字段是安全的，所以识别优先走这条路。
---@return number? questId, string? source
function T:ResolveQuestIdFromOwner(owner)
    if not owner then return nil end

    -- 1) 帧上直接挂任务 ID（Questie 追踪条、部分任务插件都是这个写法）
    for _, key in ipairs({ "questId", "questID", "QuestId", "questid" }) do
        local value = SafeNumber(owner, key)
        if value then return value, "owner." .. key end
    end

    -- 2) 帧上挂着一个任务表
    local questOk, quest = pcall(function() return owner.quest end)
    if questOk and type(quest) == "table" then
        for _, key in ipairs({ "Id", "id", "questId", "questID" }) do
            local value = SafeNumber(quest, key)
            if value then return value, "owner.quest." .. key end
        end
    end

    -- 3) Questie 追踪条会用 expectedQuest 存一份副本
    local expectedOk, expected = pcall(function() return owner.expectedQuest end)
    if expectedOk and type(expected) == "table" then
        for _, key in ipairs({ "Id", "id" }) do
            local value = SafeNumber(expected, key)
            if value then return value, "owner.expectedQuest." .. key end
        end
    end

    -- 4) Questie 的地图/小地图图标把任务数据放在 owner.data 里（MapIconTooltip 用 data.Id）
    local dataOk, data = pcall(function() return owner.data end)
    if dataOk and type(data) == "table" then
        for _, key in ipairs({ "Id", "id", "questId", "questID" }) do
            local value = SafeNumber(data, key)
            if value then return value, "owner.data." .. key end
        end
    end

    -- 5) 任务日志标题按钮：GetID() 就是日志索引
    local name = SafeName(owner)
    local index = SafeMethodNumber(owner, "GetID")
    if index and IsQuestLogButton(owner, name) then
        local questId = D.GetQuestIdByIndex and D:GetQuestIdByIndex(index)
        if questId then return questId, "QuestLog index " .. index end
    end

    return nil, name and ("owner=" .. name) or "owner=<unnamed>"
end

function T:DetectQuestId(tip)
    -- 0) 最省事的一种：插件（Questie 地图图标就是）直接把任务 ID 挂在提示对象上
    local tipQuestId = SafeNumber(tip, "questId")
    if tipQuestId then
        QCT.Log:Add("detect", "识别成功: tip.questId ->", tipQuestId)
        return tipQuestId
    end

    -- 1) 帧字段里的数字 ID
    local owner = CurrentOwner(tip)

    local questId, source = self:ResolveQuestIdFromOwner(owner)
    if questId then
        QCT.Log:Add("detect", "识别成功:", source, "->", questId)
        return questId
    end

    -- 兜底：读提示文本做标题匹配。
    -- 这个客户端会把这类文本标成 secret value，一参与比较就抛错，所以整段包在 pcall 里。
    if not (tip.IsShown and tip:IsShown()) then return nil end

    local ok, found = pcall(function()
        local lines = tip.NumLines and tip:NumLines() or 0
        if lines < 1 then return nil end
        for index = 1, math.min(2, lines) do
            local fontString = GetTipFontString(tip, index, "left")
            if fontString then
                local text = fontString:GetText()
                if text then
                    local id = D:FindQuestIdByTitle(text)
                    if id then return id end
                end
            end
        end
        return nil
    end)

    if not ok then
        QCT.Log:Add("detect", "读提示文本被拒绝(secret value)，只能靠帧字段识别 | 帧:", tostring(source))
        return nil
    end
    if found then
        QCT.Log:Add("detect", "靠标题匹配识别到:", found)
        return found
    end

    QCT.Log:Add("detect", "未识别 | 帧:", tostring(source))
    return nil
end

--------------------------------------------------------------------------------
-- 与 GameTooltip 同步
--------------------------------------------------------------------------------

local pendingCheck = false

-- 前向声明：Refresh 里也要用（定义在下面，因为要用到 DescribeFrameChain）
local ExplainOpened

local function ScheduleCheck()
    if pendingCheck then return end
    pendingCheck = true
    C_Timer.After(0, function()
        pendingCheck = false
        T:Refresh()
    end)
end

---@param force boolean? 忽略缓存强制重建（设置改动时用）
function T:Refresh(force)
    local tip = _G.GameTooltip
    local owner = CurrentOwner(tip)
    if owner then self.owner = owner end

    -- 详情窗里我们自己给物品链接弹的提示：owner 是详情窗的内容帧（带 qctLinks 标记），
    -- 那是物品提示，不是任务提示，不能当任务去识别
    if owner and owner.qctLinks then
        self:Hide()
        return
    end

    local state = self.state
    if not state or state.tip ~= tip or not tip:IsShown() then
        self:Hide()
        return
    end
    state.owner = owner
    -- 记下最近一次悬停的地图目标：鼠标轻微一动，GameTooltip 会先隐藏再重设 owner，
    -- 正好在那个瞬间按 Shift 就会被当成「没悬停任何东西」。这里留个兜底。
    self.owner = owner
    self.ownerTime = GetTime()

    -- 先识别任务：面板关着也要识别，因为地图上「按住 Shift」要靠它
    if not state.questId then
        state.questId = self:DetectQuestId(tip)
    end

    if not state.questId then
        self:Hide()
        return
    end
    self.lastQuestId = state.questId

    -- 地图上按住 Shift：直接开详情窗，不弹面板（地图已经关掉时不许开，见 OnModifierChanged）
    if IsChainKeyDown() and IsMapQuestIcon(owner) and IsWorldMapOpen() and QCT.Window then
        QCT.Log:Add("shift", "开详情窗 | 任务:", state.questId, "| 链:", self:DescribeFrameChain(owner))
        self:Hide()
        local window = QCT.Window
        if not window:IsShown() or window.questId ~= state.questId then
            local ok, err = pcall(window.Open, window, state.questId)
            if not ok then QCT:Trace("window", "打开详情窗失败:", tostring(err)) end
        end
        if ExplainOpened then ExplainOpened(owner, state.questId) end
        return
    end

    -- 聊天框里不弹：玩家在那儿是要复制/点击链接
    if owner and IsChatFrame(owner) then
        self:Hide()
        return
    end

    -- 悬停面板的显示范围：off（默认，完全不弹）/ map（只在世界地图）/ all（全部位置）
    local mode = (QCT.db and QCT.db.panelMode) or "off"
    if mode == "off" then
        self:Hide()
        return
    end
    if mode == "map" and not IsMapQuestIcon(owner) then
        self:Hide()
        return
    end

    -- 同一个任务、面板还开着，就不重复重建
    if not force and self.builtQuestId == state.questId
        and self.panel and self.panel:IsShown() then
        return
    end

    self:Update(state.questId)
end

--------------------------------------------------------------------------------
-- 钩子
--------------------------------------------------------------------------------

function T:OnQuestLogButtonEnter(button)
    local questId = D.GetQuestIdByIndex and D:GetQuestIdByIndex(button:GetID() or 0)
    if not questId then return end
    self.owner = button
    self.lastQuestId = questId
    local state = self.state
    if not state or state.tip ~= GameTooltip then return end
    state.questId = questId
    QCT.Log:Add("questlog", "按钮进入 | 索引:", button:GetID(), "->", questId)
    ScheduleCheck()
end

function T:InstallQuestLogHooks()
    -- 1) 经典任务日志的全局事件处理器（只包一次，避免多次调用层层嵌套）
    if not self.hookedGlobal and type(QuestLogTitleButton_OnEnter) == "function" then
        local original = QuestLogTitleButton_OnEnter
        QuestLogTitleButton_OnEnter = function(self, ...)
            original(self, ...)
            local ok, err = pcall(T.OnQuestLogButtonEnter, T, self)
            if not ok then QCT:Debug("任务日志 OnEnter 处理失败:", tostring(err)) end
        end
        self.hookedGlobal = true
    end

    -- 2) 逐个按钮挂 OnEnter（按钮是任务日志打开时才创建的，所以要能反复补挂）
    local count = 0
    for index = 1, 40 do
        local button = _G["QuestLogTitle" .. index] or _G["QuestLogQuestTitleButton" .. index]
        if button and button.HookScript then
            self.hookedButtons = self.hookedButtons or {}
            if not self.hookedButtons[button] then
                local ok = pcall(button.HookScript, button, "OnEnter", function(btn)
                    local hookOk, err = pcall(T.OnQuestLogButtonEnter, T, btn)
                    if not hookOk then QCT:Debug("按钮 OnEnter 处理失败:", tostring(err)) end
                end)
                if ok then self.hookedButtons[button] = true end
            end
            count = count + 1
        end
    end
    self.buttonCount = count
    QCT.Log:Add("hooks", "任务日志按钮:", count, "| 全局处理器:", self.hookedGlobal and "已挂" or "不存在")
end

---打开整条任务链详情窗。
---@param questId number?
function T:OpenChainWindow(questId)
    if not QCT.Window then return end
    if not questId then
        QCT:Print(L["没有可显示的任务：先把鼠标移到任务上，或先打开任务日志。"])
        return
    end
    local ok, err = pcall(QCT.Window.Open, QCT.Window, questId)
    if not ok then QCT:Trace("window", "打开详情窗失败:", tostring(err)) end
end

---把「为什么没开窗」说清楚，一行，直接进聊天框。
---这一步是有意保留的：地图图标这条路走不通时，玩家按一下 Shift 就能看到原因，
---不用再来回问「能不能弹」「弹了没有」。
---同一个帧、同一个原因只解释一次，整个会话最多 6 条，正常游戏时不会刷屏。
local explainedCount = 0
local explainedSeen = {}

---@param owner table?
---@param questId number?
local function ExplainNoWindow(owner, questId)
    -- 默认静默。设置里勾了「聊天框显示诊断信息」才说话。
    if not (QCT.db and QCT.db.diag) then return end
    -- 聊天框本来就不该弹，这个情况不需要解释，否则在聊天框按 Shift 会被刷屏
    if owner and IsChatFrame(owner) then return end

    local reason
    if not owner then
        reason = "拿不到提示框的持有者"
    else
        local miniOk, miniValue = pcall(function() return owner.miniMapIcon end)
        local mini = miniOk and miniValue or nil
        if mini == true then
            reason = "这是小地图图标（小地图不弹）"
        elseif IsQuestLogButton(owner) then
            reason = "这是任务日志里的一行（Shift 要留给「链接到聊天框」）"
        elseif IsChatFrame(owner) then
            reason = "这是聊天框"
        elseif not IsMapQuestIcon(owner) then
            reason = "没被认成世界地图上的任务图标"
        elseif not questId then
            reason = "认成地图图标了，但没识别出任务 ID"
        else
            reason = "未知"
        end
    end

    local key = (SafeName(owner) or "<无名>") .. "|" .. reason
    if explainedSeen[key] or explainedCount >= 6 then return end
    explainedSeen[key] = true
    explainedCount = explainedCount + 1

    QCT:Print("Shift 没开窗：", reason)
    if not owner then return end

    local miniOk, miniValue = pcall(function() return owner.miniMapIcon end)
    QCT:Print("  帧:", SafeName(owner) or "<无名>",
        "| 类型:", tostring(QuestieIconKind(owner)),
        "| miniMapIcon:", tostring(miniOk and miniValue or "?"),
        "| 世界地图:", IsWorldMapOpen() and "开" or "关",
        "| 任务:", tostring(questId))
    QCT:Print("  祖先链:", T:DescribeFrameChain(owner))
end

---开窗成功时也记一条（同一帧同一任务只说一次）。
---为什么要说：开窗「成功」也可能是误判（比如在地图旁边的任务列表上按了 Shift），
---没有这条输出就不知道到底是哪个帧被当成了地图标记。
local openedCount = 0
local openedSeen = {}

---@param owner table?
---@param questId number?
ExplainOpened = function(owner, questId)
    -- 和「没开窗」的诊断同一个开关，默认关闭
    if not (QCT.db and QCT.db.diag) then return end

    local key = (SafeName(owner) or "<无名>") .. "|" .. tostring(questId)
    if openedSeen[key] or openedCount >= 6 then return end
    openedSeen[key] = true
    openedCount = openedCount + 1

    QCT:Print("已开窗：任务", tostring(questId),
        "| 帧:", SafeName(owner) or "<无名>",
        "| 画布内:", IsOnMapCanvas(owner) and "是" or "否")
    if owner then
        QCT:Print("  祖先链:", T:DescribeFrameChain(owner))
    end
end

---从「当前鼠标悬停的任务」尝试开窗。修饰键和自定义热键共用这一段。
---@param source string? "modifier" / "hotkey"，只用于日志区分是哪条路进来的
function T:TryOpenFromHover(source)
    local tip = _G.GameTooltip
    local shown = tip ~= nil and tip.IsShown ~= nil and tip:IsShown()

    local owner
    if shown then
        local ok, value = pcall(CurrentOwner, tip)
        if ok then owner = value end
    end

    if owner then
        self.owner = owner
        self.ownerTime = GetTime()
    elseif self.owner and self.ownerTime and (GetTime() - self.ownerTime) < 5 then
        -- tooltip 刚被隐藏（鼠标抖动/重设 owner），用最近一次的目标继续
        owner = self.owner
    end

    local questId = (self.state and self.state.questId) or self.lastQuestId

    -- 就算 OnShow 钩子没装上（state 是 nil），Shift 这条路也要能用：
    -- 直接现查一次任务 ID，不依赖任何钩子。
    if not questId and tip and shown then
        local ok, id = pcall(self.DetectQuestId, self, tip)
        if ok and id then
            questId = id
            self.lastQuestId = id
            if self.state then self.state.questId = id end
        end
    end

    QCT.Log:Add("shift", source == "hotkey" and "热键触发" or "快捷键触发",
        "| tooltip:", shown and "显示" or "隐藏",
        "| 目标:", SafeName(owner) or "<无>",
        "| 是地图图标:", owner and (IsMapQuestIcon(owner) and "是" or "否") or "?",
        "| 任务:", tostring(questId),
        "| Questie图标类型:", tostring(QuestieIconKind(owner)),
        "| 在地图帧里:", owner and (IsOnWorldMap(owner) and "是" or "否") or "?",
        "| 世界地图开着:", IsWorldMapOpen() and "是" or "否",
        "| 任务日志行:", owner and (IsQuestLogButton(owner) and "是" or "否") or "?",
        "| 链:", owner and self:DescribeFrameChain(owner) or "<无>")

    if not IsMapQuestIcon(owner) then
        ExplainNoWindow(owner, questId)
        return
    end

    -- 世界地图已经关掉了：缓存里的 owner 还是关图前那个图标（帧对象还在，只是跟着地图一起不可见了），
    -- 不拦住的话，玩家按 M 关掉地图后随手再按一下 Shift，就会凭空冒出一个详情窗。
    if not IsWorldMapOpen() then
        self.owner = nil
        self.ownerTime = nil
        ExplainNoWindow(owner, questId)
        return
    end

    if not questId then
        ExplainNoWindow(owner, nil)
        return
    end
    if QCT.Window and QCT.Window:IsShown() and QCT.Window.questId == questId then return end

    self:Hide()
    self:OpenChainWindow(questId)
    ExplainOpened(owner, questId)
end

---修饰键那条路：按下配置的 Shift / Ctrl / Alt 时进来。
---为什么只在世界地图：地图上这些键没有被游戏占用；任务日志里 Shift+点击是原生的
---「把任务链接贴到聊天框」，抢了玩家就没法复制任务链接。
function T:OnModifierChanged()
    if not IsChainKeyDown() then return end
    self:TryOpenFromHover("modifier")
end

---每一步单独 pcall：这个客户端上任何一个钩子挂不上，都不能连累后面的步骤。
---尤其是 Shift 那个事件帧——它排在最后，一旦前面抛错，Shift 就彻底没反应了。
---@param label string
---@param fn function
local function TryInstall(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        QCT:Trace("hooks", "安装失败:", label, "->", tostring(err))
    end
    return ok
end

function T:Enable()
    if self.enabled then return end
    self.enabled = true

    -- 先把快捷键监听装上：它不依赖任何钩子，是最不能丢的一环
    TryInstall("MODIFIER_STATE_CHANGED", function()
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("MODIFIER_STATE_CHANGED")
        frame:SetScript("OnEvent", function(_, _, key)
            -- 只认玩家配的那一族：配成 Ctrl 时按 Shift 不再触发
            if KeyFamily(key) ~= ChainKey() then return end
            local ok, err = pcall(T.OnModifierChanged, T)
            if not ok then QCT:Debug("快捷键处理失败:", tostring(err)) end
        end)
        self.eventFrame = frame
    end)

    -- 自定义键（F / 数字键之类）走游戏绑定，登录时也要重新应用一次：
    -- 绑定只在 SaveBindings 后才持久化，换角色 / 重登都可能被冲掉
    TryInstall("自定义快捷键", function()
        self:ApplyChainKey()
    end)

    TryInstall("任务日志钩子", function()
        self:InstallQuestLogHooks()
    end)

    TryInstall("GameTooltip OnShow", function()
        GameTooltip:HookScript("OnShow", function(tip)
            T.state = {
                tip = tip,
                questId = nil,
            }
            ScheduleCheck()
        end)
    end)

    TryInstall("GameTooltip OnHide", function()
        GameTooltip:HookScript("OnHide", function()
            T.state = nil
            T.owner = nil
            T:Hide()
        end)
    end)

    -- 同一个提示里从一个任务换到另一个任务不会触发 OnShow，只会 SetOwner 重建内容。
    -- 这里只是「顺手」把 owner 记下来 + 清缓存；真正的 owner 每次都直接问 GameTooltip 要
    -- （见 CurrentOwner），所以这个钩子挂不上也不影响功能。
    TryInstall("GameTooltip SetOwner", function()
        if not hooksecurefunc then return end
        hooksecurefunc(GameTooltip, "SetOwner", function(tip, owner)
            T.owner = owner
            local state = T.state
            if not state or state.tip ~= tip then
                -- 有的客户端 / tooltip 美化插件不触发 GameTooltip 的 OnShow，
                -- state 就永远是 nil，Refresh 第一句直接 return，表现成「完全不工作」。
                -- 这里补建一次，让 SetOwner 自己就能撑起识别。
                state = { tip = tip, questId = nil }
                T.state = state
            end
            state.questId = nil
            QCT.Log:Add("setowner", "owner:", SafeName(owner) or "<unnamed>",
                "| 父级:", SafeName(select(2, pcall(function() return owner and owner:GetParent() end))) or "?",
                "| miniMapIcon:", tostring(select(2, pcall(function() return owner and owner.miniMapIcon end))))
            ScheduleCheck()
        end)
    end)

    -- 最后一道兜底：每 0.12 秒比对一次 GameTooltip 的持有者。
    -- 有的 tooltip 美化插件（Tiptac / ElvUI / TinyTooltip 之类）会接管 GameTooltip，
    -- 既可能吞掉 OnShow，也可能让 hooksecurefunc 失效，那时上面两个钩子全都收不到信号。
    -- 轮询不看事件，只看「持有者变了没有」，钩子全挂也不影响这一条。
    TryInstall("轮询兜底", function()
        local ticker = CreateFrame("Frame")
        local acc, lastOwner, lastMapOpen = 0, nil, nil
        ticker:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.12 then return end
            acc = 0

            -- 地图从「开」变「关」：关图前记下的悬停目标当场作废，
            -- 详情窗也一起收起来 —— 它是「地图上按住 Shift」的产物，
            -- 地图都关了还飘在屏幕中间，玩家按 M 之后会以为关不掉。
            local mapOpen = IsWorldMapOpen()
            if lastMapOpen == true and not mapOpen then
                T.owner = nil
                T.ownerTime = nil
                if T.state then T.state.questId = nil end
                if QCT.Window and QCT.Window:IsShown() then
                    pcall(QCT.Window.Close, QCT.Window)
                end
                QCT.Log:Add("map", "世界地图已关闭，清空悬停缓存并收起详情窗")
            end
            lastMapOpen = mapOpen

            local tip = _G.GameTooltip
            if not tip then return end
            local owner = tip.GetOwner and tip:GetOwner()
            if owner == lastOwner then return end
            lastOwner = owner
            if not owner then return end
            if not (tip.IsShown and tip:IsShown()) then return end
            T.owner = owner
            T.ownerTime = GetTime()
            if not T.state or T.state.tip ~= tip then
                T.state = { tip = tip, questId = nil }
            else
                T.state.questId = nil
            end
            QCT.Log:Add("poll", "轮询发现持有者变化:", SafeName(owner) or "<unnamed>")
            ScheduleCheck()
        end)
    end)

    -- 任务日志界面打开时补一次日志缓存
    TryInstall("QuestLogFrame OnShow", function()
        if QuestLogFrame and QuestLogFrame.HookScript then
            QuestLogFrame:HookScript("OnShow", function()
                D:RefreshQuestLog()
            end)
        end
    end)

    QCT:Trace("hooks", "钩子安装完成 | Shift 监听:", self.eventFrame and "已挂" or "失败")
end

--------------------------------------------------------------------------------
-- 自检
--------------------------------------------------------------------------------

---不依赖任务识别，直接在屏幕中间画一个内容固定的面板。
---用来判断“面板这套东西本身能不能显示”，把问题从“识别”和“显示”里分离出来。
function T:SelfTest()
    local panel = self:CreatePanel()
    local content = {
        { left = "|cff33ff99[自检] 面板可以正常显示|r", right = "|cffffd100(测试)|r" },
        { left = "|cff9d9d9d如果能看到这一段文字，说明渲染没问题|r" },
        { left = "|cff9d9d9d问题出在任务识别或数据来源上|r" },
        { left = "   |cffffd200[30] 示例任务名|r", right = "|cffffff00(3,500经验)|r |cff40ff40(可接)|r" },
        { left = "   |cff1eff00|Hitem:7073|h[断牙]|h|r" },
    }
    self:Layout(content)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:Show()

    QCT:Print("自检面板已显示在屏幕中央。尺寸 " .. tostring(panel:GetWidth()) .. " x " .. tostring(panel:GetHeight())
        .. "，可见性 " .. tostring(panel:IsShown()))
    if not panel:IsShown() then
        QCT:Print("|cffff0000面板 Show() 之后仍是隐藏状态，说明 Frame 创建有问题。|r")
    end
    return panel
end

---把当前运行状态打到聊天框，便于定位“为什么不显示”
function T:Diagnose()
    QCT:Print("---- 诊断 ----")
    QCT:Print("插件启用:", tostring(QCT.db.enabled))
    QCT:Print("Questie 数据源:", tostring(D.available), " QuestieDB:", tostring(D.mod.QuestieDB ~= nil),
        " LibQuestieDB:", tostring(D.mod.DB ~= nil))
    QCT:Print("任务日志缓存: " .. tostring(D.logCount or 0) .. " 条")
    QCT:Print("钩子: 全局处理器=" .. tostring(self.hookedGlobal) .. " 按钮数=" .. tostring(self.buttonCount))
    local owner = CurrentOwner(_G.GameTooltip) or self.owner
    QCT:Print("当前提示持有者:", SafeName(owner) or "无")
    if owner then
        QCT:Print("  图标类型:", tostring(QuestieIconKind(owner)),
            " 算地图图标:", IsMapQuestIcon(owner) and "是" or "否",
            " 在地图帧里:", IsOnWorldMap(owner) and "是" or "否",
            " 任务日志行:", IsQuestLogButton(owner) and "是" or "否")
        QCT:Print("  祖先链:", self:DescribeFrameChain(owner))
    end
    QCT:Print("世界地图开着:", IsWorldMapOpen() and "是" or "否")
    QCT:Print("面板对象:", tostring(self.panel ~= nil),
        self.panel and (" 已显示=" .. tostring(self.panel:IsShown())
            .. " 尺寸=" .. tostring(self.panel:GetWidth()) .. "x" .. tostring(self.panel:GetHeight())) or "")
    QCT:Print("最近识别: questId=" .. tostring(self.state and self.state.questId)
        .. " 已构建=" .. tostring(self.builtQuestId))
    if self.lastError then
        QCT:Print("|cffff0000最近一次渲染错误: " .. tostring(self.lastError) .. "|r")
    end
    QCT:Print("输入 |cffffff00/qct test|r 可以强制画一个测试面板，|cffffff00/qct trace|r 看后台日志。")
end
