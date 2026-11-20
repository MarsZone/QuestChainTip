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
local PAD_X, PAD_Y = 10, 8
local LINE_HEIGHT = 15
local MAX_ROWS = 42

--------------------------------------------------------------------------------
-- 面板宽度
--
-- 原来写死 330：任务名或奖励物品一长就被迫折行，「抢救数据」那种短名字也会
-- 被右侧的经验/金钱挤到第二行。现在由配置决定，默认 380（比原来宽 50px）。
-- 注意这里的 textWidth 是 upvalue，Build/Layout 都读它，改配置后由 Update 刷新。
--------------------------------------------------------------------------------

local DEFAULT_TEXT_WIDTH = 380
local MIN_TEXT_WIDTH, MAX_TEXT_WIDTH = 240, 560
local textWidth = DEFAULT_TEXT_WIDTH

---把配置值解析成实际像素；非法值/缺失都回落到默认宽度
local function ResolveTextWidth()
    local value = tonumber(QCT.db and QCT.db.panelWidth)
    if not value then value = DEFAULT_TEXT_WIDTH end
    if value < MIN_TEXT_WIDTH then value = MIN_TEXT_WIDTH end
    if value > MAX_TEXT_WIDTH then value = MAX_TEXT_WIDTH end
    return value
end
T.ResolveTextWidth = ResolveTextWidth
T.DEFAULT_TEXT_WIDTH = DEFAULT_TEXT_WIDTH

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

--------------------------------------------------------------------------------
-- 任务日志快捷键
--
-- 任务日志里 Shift+点击是原生的「把任务链接贴到聊天框」，用 Shift 开详情窗会抢掉它，
-- 所以这条路单独一个键，默认 Alt（Alt 在任务日志里没有原生用途）。
-- 只给 Alt / Ctrl / 不启用三个选择：任务日志行拿不到「任意键」的按下状态，
-- 自定义键只能靠游戏绑定，绑在任务日志上会吞掉点击，得不偿失。
--------------------------------------------------------------------------------

local QUESTLOG_KEY_ORDER = { "ALT", "CTRL", "NONE" }

local function QuestLogKey()
    local key = QCT.db and QCT.db.questLogKey
    if key == "ALT" or key == "CTRL" or key == "NONE" then return key end
    return "ALT"
end
T.QuestLogKey = QuestLogKey
T.QuestLogKeyOrder = QUESTLOG_KEY_ORDER

---任务日志用的那个键现在按着没有
local function IsQuestLogKeyDown()
    local key = QuestLogKey()
    if key == "NONE" then return false end
    if key == "CTRL" then return KeyDown("IsControlKeyDown") end
    return KeyDown("IsAltKeyDown")
end
T.IsQuestLogKeyDown = IsQuestLogKeyDown

---任务日志快捷键的显示名（不启用时走翻译）
local function QuestLogKeyLabel()
    local key = QuestLogKey()
    if key == "NONE" then return L["不启用"] end
    return key:sub(1, 1) .. key:sub(2):lower()
end
T.QuestLogKeyLabel = QuestLogKeyLabel

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

    textWidth = ResolveTextWidth()

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local panel = CreateFrame("Frame", PANEL_NAME, UIParent, template)
    panel:SetSize(textWidth + PAD_X * 2, 80)
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
        -- 之前直接把左边挤到 textWidth - rightWidth，任务名一长就被切成两行：
        -- 最后一个字掉到下一行，又被面板高度裁掉，看着像排版错乱
        -- （比如「抢救数据」显示成「抢救数」，底边框外露出一个「据」）。
        row.left:SetWidth(textWidth)
        local natural = row.left:GetStringWidth() or 0
        local stacked = rightWidth > 0 and (natural + rightWidth + 6) > textWidth

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
            local leftWidth = textWidth - rightWidth - 6
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

    panel:SetWidth(textWidth + PAD_X * 2)
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
    -- 宽度可能被玩家在设置里改过，每次重建都重新取一次
    textWidth = ResolveTextWidth()

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
            for _, wrapped in ipairs(F.Wrap(paragraph, INDENT, textWidth - 10, nil)) do
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

--------------------------------------------------------------------------------
-- 任务日志行：按键那一刻现场问鼠标
--
-- 为什么不再用钩子记下来的按钮：任务日志的标题按钮是**打开任务日志时才创建**的，
-- 而插件的钩子是在登录时装的，那一刻 QuestLogTitle1..N 全都还不存在，一个也挂不上。
-- 玩家机器上实测 `/qct qlog` 显示「任务日志按钮数: 0」「全局处理器: 不存在」，
-- 于是 questLogButton 永远是 nil，按 Alt 什么都不发生 —— 这就是三轮都没修好的原因。
-- 钩子还可能因为客户端换了全局函数名而彻底失效，指望不上。
--
-- 所以改成按键这一刻直接问 GetMouseFocus：鼠标压在哪个按钮上，就用它的 GetID()
-- 去查任务日志索引。不需要任何前置钩子，也不依赖客户端给按钮起什么名字。
--------------------------------------------------------------------------------

---这个客户端里任务日志帧可能根本不叫 QuestLogFrame —— 玩家实测 `/qct qlog` 里
---「日志帧: 无」「全局处理器: 不存在」，说明连 QuestLogTitleButton_OnEnter 都没有，
---整个任务日志是客户端自己的一套东西。
---所以不猜名字：把 _G 里所有名字带 QuestLog 的帧都收进来当候选根。
---（UI 包把日志改名成 QuestLogFrame2 / QuestLogXXX 也能覆盖到）
local questLogRoots, questLogRootsAt = nil, -1000

local function QuestLogRoots()
    local now = type(GetTime) == "function" and GetTime() or 0
    if questLogRoots and (now - questLogRootsAt) < 5 then return questLogRoots end

    local list, seen = {}, {}
    local function add(frame)
        if frame and type(frame) == "table"
            and type(frame.IsShown) == "function" and not seen[frame] then
            seen[frame] = true
            list[#list + 1] = frame
        end
    end

    add(_G.QuestLogFrame)
    add(_G.QuestLog)
    pcall(function()
        for key, value in pairs(_G) do
            if type(key) == "string" and key:find("QuestLog", 1, true) then
                add(value)
            end
        end
    end)

    -- 只留「根」：父子都在名单里时，父帧才是日志本体。
    -- 玩家实测播报里前六名全是 `QuestLogPopupDetailFrameInset` 这种小件，
    -- 真正的日志帧被挤到第七名以后 —— 播报等于白播。
    local roots = {}
    for _, frame in ipairs(list) do
        local nested, depth = false, 0
        local ok, parent = pcall(function() return frame:GetParent() end)
        local node = ok and parent or nil
        while node and depth < 8 do
            if seen[node] then nested = true; break end
            local pok, nextParent = pcall(function() return node:GetParent() end)
            node = pok and nextParent or nil
            depth = depth + 1
        end
        if not nested then roots[#roots + 1] = frame end
    end

    questLogRoots, questLogRootsAt = roots, now
    return roots
end
T.QuestLogRoots = QuestLogRoots

---这个帧现在是不是真的看得见（连祖先一起看）。
---只看自己的 IsShown 不够：任务日志关掉时，里面那些子帧的 IsShown 还是 true。
local function IsReallyShown(frame)
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
T.IsReallyShown = IsReallyShown

local function WidthOf(frame)
    if type(frame.GetWidth) ~= "function" then return 0 end
    local ok, value = pcall(frame.GetWidth, frame)
    if ok and type(value) == "number" then return value end
    return 0
end

---任务日志帧现在开着没有
local function QuestLogShown()
    for _, frame in ipairs(QuestLogRoots()) do
        -- 名字带 QuestLog 的帧很多是提示框、滚动条之类的小件，
        -- 要求它有实际宽度，免得把「关着的日志里的子件」当成日志开着
        if WidthOf(frame) >= 100 and IsReallyShown(frame) then return true end
    end
    return false
end
T.QuestLogShown = QuestLogShown

---从任务日志索引拿任务 ID。三条路，任何一条通就行：
---  1) 数据层（C_QuestLog.GetInfo / GetQuestLogTitle 的第 9 个返回值）
---  2) GetQuestLink —— 任务日志里 shift+点击能把任务链接贴到聊天框，
---     说明客户端给得出这个字符串，从里面抠 quest:1234 最可靠
---  3) 标题反查（只在这个任务本来就在日志缓存里时有效）
local function QuestIdFromLogIndex(index)
    if type(index) ~= "number" or index <= 0 then return nil end

    if D and D.GetQuestIdByIndex then
        local id = D:GetQuestIdByIndex(index)
        if id then return id end
    end

    if type(GetQuestLink) == "function" then
        local ok, link = pcall(GetQuestLink, index)
        if ok and type(link) == "string" then
            local mok, num = pcall(string.match, link, "quest:(%d+)")
            if mok and num then
                local value = tonumber(num)
                if value and value > 0 then return value end
            end
        end
    end

    return nil
end
T.QuestIdFromLogIndex = QuestIdFromLogIndex

---任务日志里「当前选中」的那一条。
---
---这个客户端是**现代 API 的客户端**（无限服 1.60.1）：`GetQuestLogSelection` 在 8.0
---就被移除了（玩家 `/qct qlog` 实测「GetQuestLogSelection: 无」），
---取而代之的是 `C_QuestLog.GetSelectedQuest()`，它直接返回任务 ID，比索引还省事。
---点一下任务行就会选中 —— 这条路不需要钩子、不需要 GetMouseFocus、也不需要帧名。
---@return number? questId, number? index
local function SelectedQuestId()
    local api = _G.C_QuestLog
    if type(api) == "table" and type(api.GetSelectedQuest) == "function" then
        local ok, questId = pcall(api.GetSelectedQuest)
        if ok and type(questId) == "number" and questId > 0 then
            return questId, nil
        end
    end

    -- 旧 API（8.0 之前）：拿到索引再换算
    if type(GetQuestLogSelection) ~= "function" then return nil, nil end
    local ok, index = pcall(GetQuestLogSelection)
    if not ok or type(index) ~= "number" or index <= 0 then return nil, nil end
    local questId = QuestIdFromLogIndex(index)
    if questId then return questId, index end
    return nil, index
end
T.SelectedQuestId = SelectedQuestId

---frame 是 ancestor 自己，或者挂在它下面
local function IsInside(frame, ancestor)
    if not frame or not ancestor then return false end
    local node = frame
    for _ = 1, 8 do
        if not node then break end
        if node == ancestor then return true end
        local ok, parent = pcall(function() return node:GetParent() end)
        node = ok and parent or nil
    end
    return false
end
T.IsInside = IsInside

---这个帧（或它的祖先）算不算任务日志里的行。
---名字带 QuestLog 的、以及挂在任务日志帧下面的都算：有的 UI 包把行按钮改成无名帧，
---只认名字会漏掉。
local function IsQuestLogRow(frame)
    if not frame then return false end
    if IsQuestLogButton(frame) then return true end
    return IsInside(frame, _G.QuestLogFrame) or IsInside(frame, _G.QuestLog)
end

---鼠标现在是不是压在这个帧上。
---优先用帧自己的 IsMouseOver；没有就退到全局 MouseIsOver。
---两个都没有的客户端，这条路直接放弃（另有「选中行」那条路兜着）。
local function IsHovered(frame)
    if not frame then return false end
    if type(frame.IsMouseOver) == "function" then
        local ok, value = pcall(frame.IsMouseOver, frame)
        if ok then return value and true or false end
    end
    if type(MouseIsOver) == "function" then
        local ok, value = pcall(MouseIsOver, frame)
        if ok then return value and true or false end
    end
    return false
end
T.IsHovered = IsHovered

---在 frame 里递归找「鼠标正压着、而且带 ID」的按钮（任务日志行就是这个形状）
local function FindHoveredRow(frame, depth)
    if not frame or depth > 4 then return nil end

    if SafeMethodNumber(frame, "GetID") and IsHovered(frame) then
        return frame
    end

    if type(frame.GetChildren) == "function" then
        local ok, children = pcall(frame.GetChildren, frame)
        if ok and type(children) == "table" then
            for _, child in ipairs(children) do
                local found = FindHoveredRow(child, depth + 1)
                if found then return found end
            end
        end
    end
    return nil
end

---鼠标正压着的帧（不依赖 GetMouseFocus）。
---
---为什么非要这么干：这个客户端**根本没有 GetMouseFocus**（玩家实测 `/qct qlog`
---里「GetMouseFocus: 无」），所以 1.5.18~1.5.23 里所有「问鼠标焦点」的路子全是死的，
---按 Alt 永远拿不到任何帧。唯一还能用的办法是 EnumerateFrames 全量遍历一遍，
---逐个问帧自己的 IsMouseOver()。代价是慢，但只在按键那一刻跑一次（MODIFIER_STATE_CHANGED
---每次按键只触发一次），不会掉帧。
---@param maxCount number? 最多返回几个（默认全部）
---@return table[] frames 层级高的在前（真正压在鼠标最上面的排第一）
local function HoveredFrames(maxCount)
    local list = {}
    if type(EnumerateFrames) ~= "function" then return list end

    local guard = 0
    pcall(function()
        local current = nil
        while true do
            local nextFrame = EnumerateFrames(current)
            if not nextFrame then break end
            current = nextFrame
            guard = guard + 1
            if guard > 30000 then break end

            local over = false
            if type(nextFrame.IsMouseOver) == "function" then
                local ok, value = pcall(nextFrame.IsMouseOver, nextFrame)
                if ok then over = value and true or false end
            end
            if not over and type(MouseIsOver) == "function" then
                local ok, value = pcall(MouseIsOver, nextFrame)
                if ok then over = value and true or false end
            end

            if over and IsReallyShown(nextFrame) then
                list[#list + 1] = nextFrame
            end
        end
    end)

    table.sort(list, function(a, b)
        local la = SafeMethodNumber(a, "GetFrameLevel") or 0
        local lb = SafeMethodNumber(b, "GetFrameLevel") or 0
        return la > lb
    end)

    if maxCount and #list > maxCount then
        local trimmed = {}
        for index = 1, maxCount do trimmed[index] = list[index] end
        return trimmed
    end
    return list
end
T.HoveredFrames = HoveredFrames

---从一个「鼠标压着的帧」推任务 ID。
---先看帧上有没有现成的任务 ID 字段（Questie 追踪条、服务器自定义任务列表都这么存），
---再沿祖先链找「算任务日志行」的帧，用它的 GetID() 当日志索引去换任务 ID。
---@return number? questId, string? source
local function QuestIdFromHoveredFrame(frame)
    if not frame then return nil, nil end

    for _, key in ipairs({ "questId", "questID", "QuestId", "questid" }) do
        local value = SafeNumber(frame, key)
        if value then return value, "鼠标下帧字段 " .. key end
    end

    -- 服务器的任务搜索列表（DungeonsForeverQuest）把整条记录挂在 row.rec 上
    local recOk, rec = pcall(function() return frame.rec end)
    if recOk and type(rec) == "table" then
        local value = SafeNumber(rec, "id") or SafeNumber(rec, "Id")
        if value then return value, "鼠标下 rec.id" end
    end

    local node, depth = frame, 0
    while node and depth < 8 do
        if IsQuestLogButton(node) then
            local index = SafeMethodNumber(node, "GetID")
            local questId = index and QuestIdFromLogIndex(index)
            if questId then
                return questId, "鼠标下日志行 " .. (SafeName(node) or "<无名>")
                    .. " 索引 " .. index
            end
        end
        local ok, parent = pcall(function() return node:GetParent() end)
        node = ok and parent or nil
        depth = depth + 1
    end

    -- 3) 有的客户端把**任务 ID 本身**塞进按钮的 GetID()，而不是日志索引。
    --    任务日志索引不会超过两百条，所以超过 200 的数字基本就是任务 ID。
    local rawId = SafeMethodNumber(frame, "GetID")
    if rawId and rawId > 200 then
        local name = SafeName(frame) or ""
        if name:find("QuestLog", 1, true) or QuestLogShown() then
            return rawId, "鼠标下按钮 ID 即任务 ID"
        end
    end

    return nil, nil
end

---鼠标现在压在哪条任务日志上？返回 questId 和一句来源说明。
---三条路，前一条走不通就走下一条：
---  1) 鼠标焦点帧（含祖先）的 GetID() → 任务日志索引
---  2) 任务日志帧里逐行问 IsMouseOver()
---  3) 提示框第一行标题反查任务日志
---@return number? questId, string? source
function T:QuestIdUnderMouse()
    local logShown = QuestLogShown()

    -- 0) 鼠标正压着的帧 —— 全量遍历 + IsMouseOver，不需要 GetMouseFocus。
    --    放在最前面：玩家停在 A 行上按 Alt，心里想的就是 A，
    --    哪怕他之前点选过 B，也不该给他弹 B。
    local hovered = HoveredFrames(8)
    for _, frame in ipairs(hovered) do
        local questId, why = QuestIdFromHoveredFrame(frame)
        if questId then return questId, why end
    end

    -- 0) 任务日志里「选中」的那一条。
    --    点一下任务行就会选中；这条路不需要钩子、不需要 GetMouseFocus、
    --    也不需要知道行按钮叫什么名字 —— 对当前这个客户端最靠谱。
    --
    --    这一步**故意不要求 QuestLogShown()**：这个客户端的任务日志很可能
    --    根本没有名字带 QuestLog 的帧（`/qct qlog` 里「全局处理器: 不存在」
    --    就是信号）。一旦把「日志开着」当门槛，这条路也会跟着废掉 ——
    --    1.5.18~1.5.21 四版全是这么废的。
    --    只挡一种情况：提示框正显示着别的对象（物品/NPC），那时按 Alt 不该抢。
    local tip = _G.GameTooltip
    local tipShown = tip ~= nil and type(tip.IsShown) == "function" and tip:IsShown()
    local owner = tipShown and CurrentOwner(tip) or nil
    local hoverOther = tipShown and owner ~= nil and not IsQuestLogRow(owner)
    if not hoverOther then
        local questId, index = SelectedQuestId()
        if questId then
            return questId, index and ("日志选中行 索引 " .. tostring(index))
                or "日志选中行（GetSelectedQuest）"
        end
    end

    -- 1) 鼠标焦点帧
    if type(GetMouseFocus) == "function" then
        local ok, focus = pcall(GetMouseFocus)
        if ok and focus then
            local node, depth = focus, 0
            while node and depth < 6 do
                -- 必须限定在任务日志里：动作条按钮也有 ID，
                -- 拿它的 ID 去查日志索引会在按 Alt 时开出完全无关的任务
                if IsQuestLogRow(node) then
                    local index = SafeMethodNumber(node, "GetID")
                    if index then
                        local questId = QuestIdFromLogIndex(index)
                        if questId then return questId, "鼠标下按钮索引 " .. index end
                    end
                end
                local pok, parent = pcall(function() return node:GetParent() end)
                node = pok and parent or nil
                depth = depth + 1
            end
        end
    end

    -- 1b) 兜底：日志开着 + 提示框正显示 + 鼠标压着一个带数字 ID 的按钮，
    --     而这个 ID 当日志索引能换出真任务 —— 那就是任务行。
    --     客户端没给行按钮起名字、或者改叫别的名字时，前面所有按名字的判断都会漏。
    if logShown and tipShown then
        for _, frame in ipairs(hovered) do
            local kindOk, kind = pcall(frame.GetObjectType, frame)
            if kindOk and kind == "Button" then
                local index = SafeMethodNumber(frame, "GetID")
                local questId = index and QuestIdFromLogIndex(index)
                if questId then
                    return questId, "鼠标下按钮索引 " .. index .. "（兜底）"
                end
            end
        end
    end

    -- 2) 任务日志帧里逐行问「鼠标压着谁」。
    --    不只看 _G.QuestLogFrame：这个客户端的日志帧可能改了名，
    --    所以把所有名字带 QuestLog 的帧都当根扫一遍。
    if logShown then
        for _, root in ipairs(QuestLogRoots()) do
            if IsReallyShown(root) and type(root.GetChildren) == "function" then
                local ok, children = pcall(root.GetChildren, root)
                if ok and type(children) == "table" then
                    for _, child in ipairs(children) do
                        local hovered = FindHoveredRow(child, 0)
                        if hovered then
                            local index = SafeMethodNumber(hovered, "GetID")
                            local questId = index and QuestIdFromLogIndex(index)
                            if questId then
                                return questId, "日志行悬停 索引 " .. index
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3) 提示框第一行标题反查（任务日志的提示框第一行就是任务名）
    if logShown then
        local tip = _G.GameTooltip
        if tip and type(tip.IsShown) == "function" then
            local sok, shown = pcall(tip.IsShown, tip)
            if sok and shown then
                local tok, found = pcall(function()
                    for index = 1, 2 do
                        local fontString = GetTipFontString(tip, index, "left")
                        if fontString then
                            local text = fontString:GetText()
                            if text and text ~= "" then
                                local id = D:FindQuestIdByTitle(text)
                                if id then return id end
                            end
                        end
                    end
                    return nil
                end)
                if tok and found then return found, "提示标题反查" end
            end
        end
    end

    return nil
end

---按了任务日志快捷键却什么也没弹时，直接把「插件到底看到了什么」播报到聊天框。
---
---为什么要自动播报而不是让玩家去输 /qct qlog：那个命令要打字，鼠标一离开任务行，
---诊断到的就不是「按 Alt 那一刻」的状态了，等于白问。这里在按键的那一刻现场取证。
---
---1.5.22 起改成**无条件播报**（限流 6 秒、每次登录最多 5 条）：
---上一版有一堆前置条件（日志开着 / 焦点是日志行 / 有行按钮），而这个客户端
---一个条件都不满足，于是「从来不出声」——玩家只知道按了没反应，我们这边什么证据都没有。
local lastMissAt = 0

---一行描述一个帧：名字(类型:ID)。播报用，越短越好。
local function DescribeFrameShort(frame)
    if not frame then return "?" end
    local kind = "?"
    local ok, value = pcall(frame.GetObjectType, frame)
    if ok and type(value) == "string" then kind = value end
    local id = SafeMethodNumber(frame, "GetID")
    return (SafeName(frame) or "<无名>") .. "(" .. kind .. (id and (":" .. id) or "") .. ")"
end

function T:ExplainQuestLogMiss()
    local now = type(GetTime) == "function" and GetTime() or 0
    if now - lastMissAt < 6 then return end
    lastMissAt = now
    self.missCount = (self.missCount or 0) + 1
    if self.missCount > 5 then return end

    local roots = QuestLogRoots()
    local logShown = QuestLogShown()
    local names = {}
    for index, frame in ipairs(roots) do
        if index > 6 then break end
        names[#names + 1] = (SafeName(frame) or "?")
            .. (IsReallyShown(frame) and "" or "(隐)")
    end

    local selection, entries
    if type(GetQuestLogSelection) == "function" then
        local ok, value = pcall(GetQuestLogSelection)
        if ok and type(value) == "number" then selection = value end
    end
    if type(GetNumQuestLogEntries) == "function" then
        local ok, value = pcall(GetNumQuestLogEntries)
        if ok and type(value) == "number" then entries = value end
    end

    -- 这个客户端是老函数没有、新表有的那一种：条目数和选中行都得问 C_QuestLog
    local cq = _G.C_QuestLog
    local cqSelected
    if type(cq) == "table" then
        if entries == nil and type(cq.GetNumQuestLogEntries) == "function" then
            local ok, value = pcall(cq.GetNumQuestLogEntries)
            if ok and type(value) == "number" then entries = value end
        end
        if type(cq.GetSelectedQuest) == "function" then
            local ok, value = pcall(cq.GetSelectedQuest)
            if ok and type(value) == "number" then cqSelected = value end
        end
    end

    local tip = _G.GameTooltip
    local tipShown = tip ~= nil and type(tip.IsShown) == "function" and tip:IsShown()
    local owner = tipShown and CurrentOwner(tip) or nil

    QCT:Print("按", QuestLogKeyLabel(), "没找到任务 | 日志帧:",
        #names > 0 and table.concat(names, ",") or "一个都没有",
        "| QuestLogFrame:", _G.QuestLogFrame and "有" or "无",
        "| 选中:", tostring(selection), "/", tostring(cqSelected),
        "| 条目:", tostring(entries),
        "| 提示框:", tipShown and "显示" or "隐藏",
        "| 持有者:", SafeName(owner) or "无")

    -- 鼠标下到底压着什么 —— 这一行才是真正能定位问题的
    local hovered = HoveredFrames(5)
    local hoverNames = {}
    for index, frame in ipairs(hovered) do
        hoverNames[index] = DescribeFrameShort(frame)
    end
    QCT:Print("  鼠标下:", #hoverNames > 0 and table.concat(hoverNames, " , ") or "什么都没压到",
        "| 日志开着:", logShown and "是" or "否")

    local questId, source = self:QuestIdUnderMouse()
    QCT:Print("  能定位到的任务:", tostring(questId), "| 来源:", tostring(source),
        "| C_QuestLog:", type(_G.C_QuestLog) == "table" and "有" or "无",
        "| GetSelectedQuest:", (type(_G.C_QuestLog) == "table"
            and type(_G.C_QuestLog.GetSelectedQuest) == "function") and "有" or "无",
        "| GetMouseFocus:", type(GetMouseFocus) == "function" and "有" or "无")
    QCT:Print("  把这两行发给作者就能定位。也可以试 /qct mouse 看更详细的信息。")
end

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
    if not button then return end

    local index = SafeMethodNumber(button, "GetID") or 0
    if index == 0 then
        -- 有的 UI 包不给行按钮设 ID，但名字还是 QuestLogTitleN，从名字尾巴上取
        local name = SafeName(button)
        if name then index = tonumber(name:match("(%d+)$")) or 0 end
    end

    local questId = index > 0 and D.GetQuestIdByIndex and D:GetQuestIdByIndex(index)
    if not questId then return end
    self.owner = button
    self.ownerTime = GetTime()
    self.lastQuestId = questId
    -- 单独记一份：任务日志那条路不依赖 tooltip owner（有的 UI 包把任务日志的提示框
    -- 换成自绘的，GameTooltip 里根本没有 owner，按 Alt 就永远找不到目标）
    self.questLogButton = button
    self.questLogQuestId = questId
    self.questLogTime = GetTime()
    local state = self.state
    if not state or state.tip ~= GameTooltip then return end
    state.questId = questId
    QCT.Log:Add("questlog", "按钮进入 | 索引:", index, "->", questId)
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

    self.hookedButtons = self.hookedButtons or {}

    -- 这一轮扫到的行按钮（用集合去重：名字循环和结构扫描会扫到同一个按钮）
    local found = {}

    ---给一个行按钮挂 OnEnter（已经挂过就不重复挂）
    local function HookRow(button)
        if not button or not button.HookScript then return end
        found[button] = true
        if self.hookedButtons[button] then return end
        local ok = pcall(button.HookScript, button, "OnEnter", function(btn)
            local hookOk, err = pcall(T.OnQuestLogButtonEnter, T, btn)
            if not hookOk then QCT:Debug("按钮 OnEnter 处理失败:", tostring(err)) end
        end)
        if ok then self.hookedButtons[button] = true end
    end

    -- 2) 按名字挂（经典客户端就是 QuestLogTitle1..N）
    for index = 1, 40 do
        HookRow(_G["QuestLogTitle" .. index] or _G["QuestLogQuestTitleButton" .. index])
    end

    -- 3) 名字对不上时，直接扫任务日志帧里的子按钮。
    --    这个客户端的任务日志是自绘的，/qct qlog 里「按钮数」一直是 0，
    --    只按名字找会一个都找不到，所以必须能按结构找。
    local logFrame = _G.QuestLogFrame or _G.QuestLog
    if logFrame and type(logFrame.GetChildren) == "function" then
        local function scan(frame, depth)
            if not frame or depth > 5 then return end
            if type(frame.GetObjectType) == "function" then
                local ok, kind = pcall(frame.GetObjectType, frame)
                if ok and kind == "Button" and SafeMethodNumber(frame, "GetID") then
                    HookRow(frame)
                end
            end
            if type(frame.GetChildren) == "function" then
                local ok, children = pcall(frame.GetChildren, frame)
                if ok and type(children) == "table" then
                    for _, child in ipairs(children) do scan(child, depth + 1) end
                end
            end
        end
        scan(logFrame, 0)
    end

    local count = 0
    for _ in pairs(found) do count = count + 1 end

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
            reason = "这是任务日志里的一行（用「任务日志快捷键」，默认 Alt）"
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
---@param viaKey string? 按下的修饰键族（SHIFT / CTRL / ALT）。
---       传了就直接用它判断该开哪条路；没传（自定义热键）才回落到 IsXxxKeyDown 查询。
function T:TryOpenFromHover(source, viaKey)
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
    -- 这个 ID 是从缓存来的还是现场查的 —— 任务日志那条键（Alt）只认现场查的
    local fromCache = questId ~= nil

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

    -- 任务日志行：单独一个键（默认 Alt）。
    -- 不能共用地图那个键：配成 Shift 时，Shift+点击是原生的「把任务链接贴到聊天框」，
    -- 抢掉玩家就没法复制任务链接了。
    if IsQuestLogButton(owner) then
        -- 事件已经把按下的键族传进来了，直接比，不依赖 IsAltKeyDown 这类 API
        -- （这个客户端上那几个函数不一定可靠，之前 Shift 能用是因为恰好没走这条路）
        local keyOk
        if viaKey then
            keyOk = (viaKey == QuestLogKey())
        else
            -- 自定义热键（source == "hotkey"）本来就不走修饰键，直接放行
            keyOk = (source == "hotkey") or IsQuestLogKeyDown()
        end
        QCT.Log:Add("questlog", "任务日志开窗判定 | 按下的键:", tostring(viaKey),
            "| 配置:", QuestLogKey(), "| 放行:", keyOk and "是" or "否",
            "| 任务:", tostring(questId))
        if not keyOk then
            ExplainNoWindow(owner, questId)
            return
        end
        -- 缓存里的是「上一次 Shift 看的任务」，跟鼠标下这一行没有任何关系。
        -- 拿它开窗 = 玩家按 Alt 弹出来的却是上次 Shift 选的那个（1.5.24 实测 bug）。
        if fromCache then
            local ok, live = pcall(self.QuestIdUnderMouse, self)
            questId = (ok and live) or nil
        end
        if not questId then
            ExplainNoWindow(owner, nil)
            return
        end
        if QCT.Window and QCT.Window:IsShown() and QCT.Window.questId == questId then return end

        self:Hide()
        self:OpenChainWindow(questId)
        ExplainOpened(owner, questId)
        return
    end

    if not IsMapQuestIcon(owner) then
        ExplainNoWindow(owner, questId)
        return
    end

    -- 按下的如果是任务日志那个键（Alt），不要在地图上开窗
    if viaKey and viaKey ~= ChainKey() then
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

---修饰键那条路：按下配置的键时进来。
---两条路各用各的键：世界地图用「详情窗快捷键」（默认 Shift），
---任务日志用「任务日志快捷键」（默认 Alt，避开原生 Shift+点击复制链接）。
---@param viaKey string? 按下的键族（SHIFT / CTRL / ALT），由事件直接带进来
function T:OnModifierChanged(viaKey)
    -- 任务日志这条路：按下键的这一刻现场问鼠标停在哪一行上。
    -- 不依赖任何钩子，也不依赖 tooltip owner（有的 UI 包把任务日志的提示框换成自绘的，
    -- GameTooltip 里根本没有 owner）。上一版靠「钩子记下的按钮 + MouseIsOver」，
    -- 但按钮是打开日志时才创建的、钩子登录时就装完了，一个都没挂上，所以永远不弹。
    if viaKey and viaKey == QuestLogKey() then
        -- 先看鼠标是不是其实在地图图标上：那种情况交给下面的地图逻辑，
        -- 否则地图上按任务日志键会去查日志，查不到就什么都不弹。
        local tip = _G.GameTooltip
        local tipShown = tip ~= nil and type(tip.IsShown) == "function" and tip:IsShown()
        local currentOwner = tipShown and CurrentOwner(tip) or nil
        local onMapIcon = currentOwner ~= nil and IsMapQuestIcon(currentOwner)

        if not onMapIcon then
            -- 1) 现场扫鼠标下压着什么（全量遍历 + 每个帧自己的 IsMouseOver），最准的一条。
            --    这个客户端**没有 GetMouseFocus**（玩家实测），也没有全局 MouseIsOver，
            --    所以只能这么问；钩子记下来的行按钮只当兜底。
            local questId, source = self:QuestIdUnderMouse()
            if questId then
                -- 用的是「日志里选中的那条」而不是鼠标下这一行时，明说一句：
                -- 不然玩家会以为 Alt 弹的是上次 Shift 看/点过的任务（1.5.24 实测反馈）。
                if source and source:find("选中行", 1, true) then
                    QCT:Print("用的是任务日志里选中的那条：#" .. tostring(questId)
                        .. "（鼠标下没识别到行；点一下目标行再按 " .. QuestLogKeyLabel() .. "）")
                end
                if not (QCT.Window and QCT.Window:IsShown() and QCT.Window.questId == questId) then
                    self:Hide()
                    self:OpenChainWindow(questId)
                end
                QCT.Log:Add("questlog", "快捷键开窗 |", tostring(source), "| 任务:", questId)
                return
            end

            -- 2) 现场扫不到，再看钩子记下的行按钮是不是还悬停着
            local row = self.questLogButton
            if row and self.questLogQuestId then
                local stillHover
                if type(row.IsMouseOver) == "function" then
                    local ok, value = pcall(row.IsMouseOver, row)
                    stillHover = ok and value and true or false
                else
                    stillHover = (GetTime() - (self.questLogTime or 0)) < 3
                end
                if stillHover then
                    questId = self.questLogQuestId
                    if not (QCT.Window and QCT.Window:IsShown() and QCT.Window.questId == questId) then
                        self:Hide()
                        self:OpenChainWindow(questId)
                    end
                    QCT.Log:Add("questlog", "行悬停开窗 | 任务:", questId)
                    return
                end
            end

            -- 3) 一条都没定位到：**绝不拿缓存开窗**。
            --    1.5.24 的实测 bug：玩家先在别处 Shift 看过任务 A，再来任务日志里按 Alt，
            --    下面的 TryOpenFromHover 会把缓存里的 A 当成「鼠标下这一行」弹出来 ——
            --    表现出来就是「Alt 弹的是上次 Shift 选的那个」。
            --    所以这里清掉缓存直接播报现场，让下一次按键从干净状态开始。
            self.questLogButton = nil
            self.questLogQuestId = nil
            self.lastQuestId = nil
            local ok, err = pcall(self.ExplainQuestLogMiss, self)
            if not ok then QCT.Log:Add("questlog", "播报失败:", tostring(err)) end
            return
        end
    end

    local windowBefore = QCT.Window and QCT.Window:IsShown() and QCT.Window.questId or nil
    self:TryOpenFromHover("modifier", viaKey)

    -- 两条路都没开出窗：把现场证据播报出来，省得玩家再回来问「按了没反应」。
    if viaKey and viaKey == QuestLogKey() then
        local windowNow = QCT.Window and QCT.Window:IsShown() and QCT.Window.questId or nil
        if not windowNow or windowNow == windowBefore then
            local ok, err = pcall(self.ExplainQuestLogMiss, self)
            if not ok then QCT.Log:Add("questlog", "播报失败:", tostring(err)) end
        end
    end
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
            -- 只认玩家配的那两族：地图用 chainKey，任务日志用 questLogKey
            local family = KeyFamily(key)
            if family ~= ChainKey() and family ~= QuestLogKey() then return end
            local ok, err = pcall(T.OnModifierChanged, T, family)
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

    -- 任务日志界面打开时补一次日志缓存，顺便补挂按钮钩子。
    -- 钩子必须在这里重挂：登录时任务日志还没建，QuestLogTitle1..N 一个都不存在，
    -- 只在 Enable() 里挂一次的话按钮数永远是 0。
    TryInstall("QuestLogFrame OnShow", function()
        local frame = _G.QuestLogFrame or _G.QuestLog
        if frame and frame.HookScript then
            frame:HookScript("OnShow", function()
                D:RefreshQuestLog()
                local ok, err = pcall(T.InstallQuestLogHooks, T)
                if not ok then QCT:Debug("补挂任务日志钩子失败:", tostring(err)) end
            end)
        end
    end)

    -- QUEST_LOG_UPDATE 也补一次：有的客户端任务日志是复用的，不会再触发 OnShow
    TryInstall("QUEST_LOG_UPDATE", function()
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("QUEST_LOG_UPDATE")
        frame:SetScript("OnEvent", function()
            local ok, err = pcall(T.InstallQuestLogHooks, T)
            if not ok then QCT:Debug("补挂任务日志钩子失败:", tostring(err)) end
        end)
        self.questLogEventFrame = frame
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

---`/qct mouse` 用：鼠标现在到底压在哪。
---这个客户端没有 GetMouseFocus，所以主角是「全量遍历 + IsMouseOver」，
---GetMouseFocus 只作为别的客户端的补充信息打一行。
function T:DiagnoseMouse()
    QCT:Print("---- 鼠标诊断 ----")

    QCT:Print("GetMouseFocus:", type(GetMouseFocus) == "function" and "有" or "没有（这个客户端没有）",
        "| EnumerateFrames:", type(EnumerateFrames) == "function" and "有" or "没有",
        "| MouseIsOver:", type(MouseIsOver) == "function" and "有" or "没有")

    QCT:Print("任务日志开着:", QuestLogShown() and "是" or "否",
        "| QuestLogFrame:", _G.QuestLogFrame and "有" or "无")

    local hovered = HoveredFrames(10)
    QCT:Print("鼠标压着的帧:", #hovered .. " 个")
    for index, frame in ipairs(hovered) do
        QCT:Print("  " .. index .. ") " .. DescribeFrameShort(frame),
            "| 日志行:", IsQuestLogRow(frame) and "是" or "否")
        QCT:Print("     祖先链:", self:DescribeFrameChain(frame))
    end
    if #hovered == 0 then
        QCT:Print("  一个都没压到 —— 要么鼠标在空白处，要么这个客户端的 IsMouseOver 不可用。")
    end

    local tip = _G.GameTooltip
    local tipShown = tip ~= nil and type(tip.IsShown) == "function" and tip:IsShown()
    local owner = tipShown and CurrentOwner(tip) or nil
    QCT:Print("提示框:", tipShown and "显示" or "隐藏",
        "| 持有者:", SafeName(owner) or "无",
        "| 算任务日志行:", tostring(owner ~= nil and IsQuestLogButton(owner) or false))

    local questId, source = self:QuestIdUnderMouse()
    QCT:Print("鼠标下能定位到的任务:", tostring(questId), "| 来源:", tostring(source))
end

---`/qct qlog` 用：任务日志这条快捷键路的完整状态。
---「Alt 按了没反应」时，光看代码猜不出来，得看实际是哪一环断了。
function T:DiagnoseQuestLog()
    QCT:Print("---- 任务日志快捷键诊断 ----")
    QCT:Print("配置的键:", QuestLogKey())

    local roots = QuestLogRoots()
    local names = {}
    for index, frame in ipairs(roots) do
        if index > 8 then break end
        names[#names + 1] = (SafeName(frame) or "?")
            .. (IsReallyShown(frame) and "[显示]" or "[隐藏]")
            .. "宽" .. math.floor(WidthOf(frame))
    end
    QCT:Print("名字带 QuestLog 的帧:", #names > 0 and table.concat(names, " ; ") or "一个都没有")
    QCT:Print("任务日志开着:", QuestLogShown() and "是" or "否")

    -- 这个客户端最要紧的三件事：能不能拿到「选中行」和「任务链接」
    local selection, entries, link
    if type(GetQuestLogSelection) == "function" then
        local ok, value = pcall(GetQuestLogSelection)
        if ok and type(value) == "number" then selection = value end
    end
    if type(GetNumQuestLogEntries) == "function" then
        local ok, value = pcall(GetNumQuestLogEntries)
        if ok and type(value) == "number" then entries = value end
    end
    local cqEarly = _G.C_QuestLog
    if entries == nil and type(cqEarly) == "table"
        and type(cqEarly.GetNumQuestLogEntries) == "function" then
        local ok, value = pcall(cqEarly.GetNumQuestLogEntries)
        if ok and type(value) == "number" then entries = value end
    end
    if type(GetQuestLink) == "function" and type(selection) == "number" and selection > 0 then
        local ok, value = pcall(GetQuestLink, selection)
        if ok and type(value) == "string" then link = value end
    end
    QCT:Print("选中行:", tostring(selection), "| 日志条目数:", tostring(entries),
        "| 选中行的链接:", link and link:sub(1, 40) or "取不到")

    local hovered = HoveredFrames(5)
    local hoverNames = {}
    for index, frame in ipairs(hovered) do
        hoverNames[index] = DescribeFrameShort(frame)
    end
    QCT:Print("鼠标下:", #hoverNames > 0 and table.concat(hoverNames, " , ") or "什么都没压到")

    local questId, source = self:QuestIdUnderMouse()
    QCT:Print("能定位到的任务:", tostring(questId), "| 来源:", tostring(source))

    local tip = _G.GameTooltip
    local shown = tip ~= nil and type(tip.IsShown) == "function" and tip:IsShown()
    local owner = shown and CurrentOwner(tip) or nil
    QCT:Print("提示框:", shown and "显示" or "隐藏", "| 持有者:", SafeName(owner) or "无",
        "| 算任务日志行:", tostring(owner ~= nil and IsQuestLogRow(owner) or false))

    QCT:Print("GetMouseFocus:", type(GetMouseFocus) == "function" and "有" or "没有",
        "| GetQuestLogSelection:", type(GetQuestLogSelection) == "function" and "有" or "没有",
        "| GetQuestLink:", type(GetQuestLink) == "function" and "有" or "没有")
    -- 这个客户端是现代 API：这两张表在不在，决定了走哪条路
    local cq = _G.C_QuestLog
    QCT:Print("C_QuestLog:", type(cq) == "table" and "有" or "没有",
        "| C_QuestLog.GetSelectedQuest:", (type(cq) == "table"
            and type(cq.GetSelectedQuest) == "function") and "有" or "没有",
        "| C_QuestLog.GetInfo:", (type(cq) == "table"
            and type(cq.GetInfo) == "function") and "有" or "没有",
        "| C_NamePlate:", type(_G.C_NamePlate) == "table" and "有" or "没有")
    if type(cq) == "table" and type(cq.GetSelectedQuest) == "function" then
        local ok, value = pcall(cq.GetSelectedQuest)
        QCT:Print("当前选中的任务:", ok and tostring(value) or "取不到")
    end
    QCT:Print("已挂钩子行数:", tostring(self.buttonCount or 0),
        "| 全局处理器:", tostring(self.hookedGlobal and "已挂" or "不存在"))
    QCT:Print("提示：鼠标停在任务行上（或先点一下让它选中）再按 "
        .. QuestLogKeyLabel() .. "，应能打开详情窗。")
end

---把当前运行状态打到聊天框，便于定位“为什么不显示”
function T:Diagnose()
    QCT:Print("---- 诊断 ----")
    QCT:Print(L.F("插件版本: %s", tostring(QCT.VERSION or "?")))
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
