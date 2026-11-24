--[[
数据层：统一从 Questie / QuestieDB 读取任务信息，并给出兜底实现。
所有外部调用都做了 pcall 保护，Questie 版本变化时不会让插件报错崩溃。
]]

local ADDON, ns = ...
local QCT = ns
local F = QCT.Format
local D = {}
QCT.Data = D

local mod = {}
D.mod = mod

local pcall, type, tostring, tonumber = pcall, type, tostring, tonumber

-- 前置声明：GetDescription 等函数定义在 SafeString 实现之前，
-- 若这里不声明，那些函数里的 SafeString 会被当成全局变量（nil），一调用就报
-- "attempt to call a nil value"。真正的实现在下面「奖励接口探测」之前。
local SafeString

--------------------------------------------------------------------------------
-- 初始化：拿到 Questie 的模块
--------------------------------------------------------------------------------

local function safeImport(name)
    if not (QuestieLoader and type(QuestieLoader.ImportModule) == "function") then return nil end
    local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    if ok then return module end
    return nil
end

---初始化/重试导入 Questie 模块。
---Questie 的模块是在它自己的 PLAYER_LOGIN 里才建好的，谁先加载不一定，
---所以这里允许反复调用：这次没拿到，下次（悬停时）再试，不能一次失败就永久放弃。
function D:Init()
    if self.available then return true end
    self.initialized = true

    mod.QuestieDB = safeImport("QuestieDB") or mod.QuestieDB
    mod.QuestieLib = safeImport("QuestieLib") or mod.QuestieLib
    mod.QuestXP = safeImport("QuestXP") or mod.QuestXP
    mod.QuestieReputation = safeImport("QuestieReputation") or mod.QuestieReputation
    mod.QuestieEvent = safeImport("QuestieEvent") or mod.QuestieEvent
    mod.ZoneDB = safeImport("ZoneDB") or mod.ZoneDB
    mod.QuestiePlayer = safeImport("QuestiePlayer") or mod.QuestiePlayer
    mod.QuestieCorrections = safeImport("QuestieCorrections") or mod.QuestieCorrections
    -- QuestieDB 独立插件暴露的公共实体
    mod.DB = _G.LibQuestieDB or mod.DB

    local wasAvailable = self.available
    self.available = (mod.QuestieDB ~= nil) or (mod.DB ~= nil)
    if self.available and not wasAvailable then
        -- 刚拿到数据源，之前缓存的 nil 结果全部作废
        self:InvalidateCache()
    end
    return self.available
end

function D:InvalidateCache()
    self.questCache = {}
    self.stateCache = {}
    F.ClearWrapCache()
end

--------------------------------------------------------------------------------
-- 任务基础信息
--------------------------------------------------------------------------------

local function newCache()
    return {}
end

---返回 Questie 风格的 quest 表（或最小兜底表）。未知任务返回 nil。
---@param questId number
---@return table?
function D:GetQuest(questId)
    questId = tonumber(questId)
    if not questId or questId <= 0 then return nil end

    self.questCache = self.questCache or newCache()
    local cached = self.questCache[questId]
    if cached ~= nil then
        return cached or nil
    end

    local quest

    if not self.available then self:Init() end

    if mod.QuestieDB then
        local ok, result = pcall(mod.QuestieDB.GetQuest, mod.QuestieDB, questId)
        if ok and type(result) == "table" then
            quest = result
        end
    end

    if not quest and mod.DB and mod.DB.Quest then
        local entity = mod.DB.Quest
        local ok, name = pcall(entity.name, questId)
        if ok and type(name) == "string" then
            local function field(key)
                local fok, value = pcall(entity[key], questId)
                if fok then return value end
                return nil
            end
            quest = {
                Id = questId,
                name = name,
                level = field("questLevel"),
                requiredLevel = field("requiredLevel"),
                nextQuestInChain = field("nextQuestInChain"),
                reputationReward = field("reputationReward"),
                objectivesText = field("objectivesText"),
                zoneOrSort = field("zoneOrSort"),
                questFlags = field("questFlags"),
                preQuestSingle = field("preQuestSingle"),
                preQuestGroup = field("preQuestGroup"),
                breadcrumbs = field("breadcrumbs"),
            }
            quest.Description = quest.objectivesText
        end
    end

    -- 最后兜底：Questie 数据不可用时，用客户端自己的信息拼一个最小任务表。
    -- 这样至少还能显示任务名、任务目标和奖励，而不是整个面板不显示。
    if not quest then
        local title
        if C_QuestLog and type(C_QuestLog.GetTitleForQuestID) == "function" then
            local ok, value = pcall(C_QuestLog.GetTitleForQuestID, questId)
            if ok and type(value) == "string" and value ~= "" then title = value end
        end
        if not title then
            local entry = self.logTitleById and self.logTitleById[questId]
            if type(entry) == "string" then title = entry end
        end
        if title then
            quest = { Id = questId, name = title, minimal = true }
        end
    end

    self.questCache[questId] = quest or false
    return quest
end

function D:GetName(questId)
    local quest = self:GetQuest(questId)
    return quest and quest.name or nil
end

function D:GetLevel(questId)
    local quest = self:GetQuest(questId)
    if not quest then return 0 end
    return tonumber(quest.level) or tonumber(quest.questLevel) or 0
end

---任务描述（目标文本）。返回字符串数组。
---@return string[]
function D:GetDescription(questId)
    local quest = self:GetQuest(questId)
    if not quest then return {} end
    local desc = quest.Description or quest.objectivesText
    if type(desc) == "string" then
        if desc ~= "" then return { desc } end
    elseif type(desc) == "table" then
        local out = {}
        for _, line in ipairs(desc) do
            if type(line) == "string" and line ~= "" then
                out[#out + 1] = line
            end
        end
        if #out > 0 then return out end
    end

    -- Questie 没数据时的兜底：直接问客户端
    local function clientObjectives(id)
        -- 1) C_QuestLog.GetQuestObjectives(questID) 直接返回目标文本
        if C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function" then
            local ok, text = pcall(C_QuestLog.GetQuestObjectives, id)
            if ok then
                local safe = SafeString(text)
                if safe and safe ~= "" then return safe end
            end
        end
        -- 2) 退一步：用任务日志索引取描述（GetQuestLogQuestText 收的是索引，不是 ID）
        local index = self.logIndexById and self.logIndexById[id]
        if index and type(GetQuestLogQuestText) == "function" then
            local ok, text = pcall(GetQuestLogQuestText, index)
            if ok then
                local safe = SafeString(text)
                if safe and safe ~= "" then return safe end
            end
        end
        return nil
    end

    local text = clientObjectives(questId)
    if text then return { text } end
    return {}
end

function D:GetNext(questId)
    local quest = self:GetQuest(questId)
    if not quest then return nil end
    local id = tonumber(quest.nextQuestInChain)
    if id and id > 0 then return id end
    return nil
end

function D:GetPrerequisites(questId)
    local quest = self:GetQuest(questId)
    if not quest then return {}, {} end
    local single, group = {}, {}
    for _, id in ipairs(quest.preQuestSingle or {}) do
        if tonumber(id) and id > 0 then single[#single + 1] = id end
    end
    for _, id in ipairs(quest.preQuestGroup or {}) do
        if tonumber(id) and id > 0 then group[#group + 1] = id end
    end
    return single, group
end

--------------------------------------------------------------------------------
-- 任务状态
--------------------------------------------------------------------------------

function D:IsCompleted(questId)
    if Questie and Questie.db and Questie.db.char and Questie.db.char.complete then
        return Questie.db.char.complete[questId] == true
    end
    if IsQuestFlaggedCompleted then
        local ok, done = pcall(IsQuestFlaggedCompleted, questId)
        if ok then return done == true or done == 1 end
    end
    return false
end

function D:IsInLog(questId)
    if C_QuestLog and type(C_QuestLog.IsOnQuest) == "function" then
        local ok, onQuest = pcall(C_QuestLog.IsOnQuest, questId)
        if ok and onQuest ~= nil then return onQuest == true end
    end
    return (self.logById and self.logById[questId]) == true
end

---@return string state, string? reason
---  state: "active" | "completed" | "available" | "locked" | "unknown"
function D:GetState(questId)
    self.stateCache = self.stateCache or {}
    local cached = self.stateCache[questId]
    if cached then return cached.state, cached.reason end

    local state, reason = "unknown", nil

    if self:IsCompleted(questId) then
        state = "completed"
    elseif self:IsInLog(questId) then
        state = "active"
    else
        local QDB = mod.QuestieDB
        if QDB and type(QDB.IsDoableVerbose) == "function" then
            local ok, text, _, code = pcall(QDB.IsDoableVerbose, questId, false, true, true)
            if ok then
                if code == nil or code == 0 then
                    state = "available"
                elseif code == 1 then
                    state = "completed"
                elseif code == 2 then
                    state = "active"
                else
                    state = "locked"
                    reason = text
                end
            end
        elseif not self:IsCompleted(questId) then
            state = "available"
        end
    end

    self.stateCache[questId] = { state = state, reason = reason }
    return state, reason
end

--------------------------------------------------------------------------------
-- 奖励
--------------------------------------------------------------------------------

function D:GetXP(questId)
    local QuestXP = mod.QuestXP
    if QuestXP and type(QuestXP.GetQuestLogRewardXP) == "function" then
        local ok, xp = pcall(QuestXP.GetQuestLogRewardXP, QuestXP, questId, false)
        if ok and type(xp) == "number" and xp > 0 then return xp end
    end

    if GetQuestLogRewardXP then
        local ok, xp = pcall(GetQuestLogRewardXP, questId)
        if ok and type(xp) == "number" and xp > 0 then return xp end
    end

    return 0
end

function D:GetMoney(questId)
    local QuestXP = mod.QuestXP
    if QuestXP and type(QuestXP.GetQuestRewardMoney) == "function" then
        local ok, money = pcall(QuestXP.GetQuestRewardMoney, questId)
        if ok and type(money) == "number" then return money end
    end
    if GetQuestLogRewardMoney then
        local ok, money = pcall(GetQuestLogRewardMoney, questId)
        if ok and type(money) == "number" then return money end
    end
    return 0
end

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 1.00, 1.00, 1.00 },
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.00, 0.50, 0.00 },
    [6] = { 1.00, 0.80, 0.10 },
    [7] = { 0.90, 0.90, 0.90 },
}

---确认一个值是可以安全参与字符串拼接的普通字符串。
---这个客户端的 secret value 一参与拼接就抛错，所以先 pcall 试一次。
function SafeString(value)
    if type(value) ~= "string" then return nil end
    local ok, text = pcall(string.format, "%s", value)
    if not ok or type(text) ~= "string" then return nil end
    return text
end

---查物品信息。不同客户端可能只有 GetItemInfo 或只有 C_Item.GetItemInfo，
---两边都没有就返回 nil，绝不让调用方炸掉。
local function ItemInfo(itemID)
    local fn = GetItemInfo
    if type(fn) ~= "function" then
        fn = _G.C_Item and _G.C_Item.GetItemInfo
    end
    if type(fn) ~= "function" then return nil end

    local ok, name, link, quality = pcall(fn, itemID)
    if not ok then return nil end
    if type(quality) ~= "number" then quality = nil end
    return SafeString(name), SafeString(link), quality
end

local function ItemQualityColor(quality)
    local fn = _G.GetItemQualityColor
    if type(fn) == "function" then
        local ok, r, g, b = pcall(fn, quality or 1)
        if ok and type(r) == "number" then return r, g, b end
    end
    local entry = QUALITY_COLORS[quality or 1] or QUALITY_COLORS[1]
    return entry[1], entry[2], entry[3]
end

--------------------------------------------------------------------------------
-- 奖励接口探测
--
-- 背景：QuestieDB 没有「物品奖励」字段（只有 reputationReward），物品奖励只能问客户端。
-- 而客户端的 GetNumQuestLogRewards / GetQuestLogRewardInfo 传统上只对「已在任务日志里」
-- 的任务有效。为了不靠猜，这里把真实返回值原样记进日志，用实际数据判断到底行不行。
--------------------------------------------------------------------------------

local probedQuests = {}

local function Describe(value)
    local kind = type(value)
    if value == nil then return "nil" end
    if kind == "string" then
        return "string:" .. (SafeString(value) or "<secret>")
    end
    if kind == "number" or kind == "boolean" then
        return kind .. ":" .. tostring(value)
    end
    return kind
end

---@param questId number
---@param force boolean? 忽略"已探测过"的标记
function D:ProbeRewardAPI(questId, force)
    questId = tonumber(questId)
    if not questId then return end
    if probedQuests[questId] and not force then return end
    probedQuests[questId] = true

    local inLog = self:IsInLog(questId)
    local countOk, count = pcall(GetNumQuestLogRewards, questId)
    QCT.Log:Add("rewards", "探测", questId,
        "| 在任务日志:", inLog and "是" or "否",
        "| GetNumQuestLogRewards ->", countOk and Describe(count) or "调用失败")

    if countOk and type(count) == "number" and count > 0 then
        local results = { pcall(GetQuestLogRewardInfo, 1, questId) }
        local parts = {}
        for index = 1, #results do
            parts[#parts + 1] = index .. "=" .. Describe(results[index])
        end
        QCT.Log:Add("rewards", "  第 1 件:", table.concat(parts, "  "))
    end

    local moneyOk, money = pcall(GetQuestLogRewardMoney, questId)
    QCT.Log:Add("rewards", "  GetQuestLogRewardMoney ->", moneyOk and Describe(money) or "调用失败")
    QCT.Log:Add("rewards", "  候选接口 | C_QuestLog.GetQuestRewardItems:",
        type(C_QuestLog and C_QuestLog.GetQuestRewardItems),
        "| C_QuestInfoSystem:", type(_G.C_QuestInfoSystem),
        "| GetQuestReward:", type(_G.GetQuestReward),
        "| GetQuestItemLink:", type(_G.GetQuestItemLink),
        "| C_Item.GetItemInfo:", type(_G.C_Item and _G.C_Item.GetItemInfo))
end

--------------------------------------------------------------------------------
-- 物品奖励：接口拿 + 本地缓存
--
-- 客户端接口只对「已在任务日志里」的任务可靠，所以把每次成功读到的物品存进存档，
-- 以后同一条任务链上（哪怕已经交掉了）也能显示出来。
--------------------------------------------------------------------------------

local function BuildItemDisplay(name, quality, itemID, numItems)
    local display

    if itemID then
        local itemName, itemLink, itemQuality = ItemInfo(itemID)
        name = itemName or name
        quality = itemQuality or quality
        if itemLink then
            display = itemLink
        elseif name then
            local r, g, b = ItemQualityColor(quality)
            display = F.Hex(r, g, b, "|Hitem:" .. itemID .. "|h[" .. name .. "]|h")
        end
    elseif name then
        display = F.Hex(1, 1, 1, "[" .. name .. "]")
    end

    if display and numItems and numItems > 1 then
        display = display .. "x" .. numItems
    end
    return display
end

function D:GetCachedRewardItems(questId)
    local db = QCT.db
    local cache = db and db.rewardCache
    if type(cache) ~= "table" then return nil end

    local entry = cache[questId]
    if type(entry) ~= "table" or #entry == 0 then return nil end

    local out = {}
    for _, row in ipairs(entry) do
        local display = BuildItemDisplay(row[1], row[2], row[3], row[4])
        if display then out[#out + 1] = { text = display } end
    end
    if #out == 0 then return nil end
    return out
end

function D:CacheRewardItems(questId, items)
    local db = QCT.db
    if not db or type(items) ~= "table" or #items == 0 then return end

    db.rewardCache = db.rewardCache or {}
    local compact = {}
    for _, item in ipairs(items) do
        if item.name then
            compact[#compact + 1] = { item.name, item.quality, item.itemID, item.num }
        end
    end
    if #compact == 0 then return end
    db.rewardCache[questId] = compact
end

---@return table[] items 每项 { text = string }
function D:GetRewardItems(questId)
    local out = {}
    if type(GetNumQuestLogRewards) ~= "function" or type(GetQuestLogRewardInfo) ~= "function" then
        return self:GetCachedRewardItems(questId) or self:GetIndexedRewardItems(questId) or out
    end

    local ok, count = pcall(GetNumQuestLogRewards, questId)
    if not ok or type(count) ~= "number" or count <= 0 then
        -- 只对「不在任务日志里」的任务做探测：这才是"接口到底支不支持未接任务"的关键样本
        if not self:IsInLog(questId) then
            self:ProbeRewardAPI(questId)
        end
        -- 接口拿不到：先用存档里缓存过的（品质/链接最准），再用 QuestieDB 物品表反查
        return self:GetCachedRewardItems(questId) or self:GetIndexedRewardItems(questId) or out
    end
    if count > 12 then count = 12 end

    for i = 1, count do
        local results = { pcall(GetQuestLogRewardInfo, i, questId) }
        if results[1] then
            -- 本客户端（Questie 同款调用）的返回顺序：贴图, 名称, 数量, 品质, 是否可用, itemID
            local name, numItems, quality, itemID
            local rawName, rawNum, rawQuality = results[3], results[4], results[5]
            local rawItemID = results[7]

            if type(rawName) == "string" then name = SafeString(rawName) end
            if type(rawNum) == "number" then numItems = rawNum end
            if type(rawQuality) == "number" then quality = rawQuality end
            if type(rawItemID) == "number" and rawItemID > 0 then itemID = rawItemID end

            if not itemID then
                -- 兜底：按类型嗅探（不同客户端顺序可能有差异）
                for index = 2, #results do
                    local value = results[index]
                    if type(value) == "string" then
                        local text = SafeString(value)
                        if text and text ~= "" and not text:find("\\", 1, true) then
                            name = name or text
                        end
                    elseif type(value) == "number" and value > 1000 and not itemID then
                        itemID = value
                    end
                end
                if quality and quality > 8 then quality = nil end
            end

            local display = BuildItemDisplay(name, quality, itemID, numItems)
            if display then
                out[#out + 1] = {
                    text = display,
                    name = name,
                    quality = quality,
                    itemID = itemID,
                    num = numItems,
                }
            end
        end
    end

    if #out > 0 then
        self:CacheRewardItems(questId, out)
    else
        return self:GetCachedRewardItems(questId) or self:GetIndexedRewardItems(questId) or out
    end

    return out
end

--------------------------------------------------------------------------------
-- 物品奖励的第二个来源：QuestieDB 物品表的反向索引
--
-- 客户端的 GetNumQuestLogRewards 只认「任务日志里的任务」，所以「后续任务」原本看不到物品。
-- 但 QuestieDB 的物品表里有一个 questRewards 字段（这件物品是哪些任务的奖励），
-- 把整张物品表扫一遍就能反过来得到「任务 -> 奖励物品」，对没接的任务同样有效。
--
-- 扫描是一次性的（每会话一次，不写存档，避免存档膨胀），放在后台分帧跑，不卡画面。
--------------------------------------------------------------------------------

local SCAN_BATCH = 200        -- 每批扫多少件物品
local SCAN_INTERVAL = 0.05    -- 两批之间隔多久（秒），调大一点更不卡画面
local rewardIndex = nil      -- 会话内的反查表：questId -> { itemID, ... }
local scanState = nil        -- 正在扫描时的进度

---取物品实体。QuestieDB 是独立插件，可能比我们晚加载，
---所以每次现查，不能只在 D:Init() 里取一次（那会儿它常常还没加载完）。
local function itemEntity()
    local lib = _G.LibQuestieDB or mod.DB
    if lib and lib.Item then
        mod.DB = lib
        return lib.Item
    end
    return _G.ItemDB
end

---@return number[]? itemIDs
function D:GetItemRewardIds(questId)
    if type(rewardIndex) ~= "table" then return nil end
    local list = rewardIndex[questId]
    if type(list) == "table" and #list > 0 then return list end
    return nil
end

---把反查到的物品 ID 变成可显示的行
---@return table[]?
function D:GetIndexedRewardItems(questId)
    local ids = self:GetItemRewardIds(questId)
    if not ids then return nil end

    local entity = itemEntity()
    local out = {}
    for _, itemID in ipairs(ids) do
        local display = BuildItemDisplay(nil, nil, itemID, nil)
        if not display and entity and type(entity.name) == "function" then
            -- 客户端还不认识这件物品：用 QuestieDB 的名字兜底
            local ok, value = pcall(entity.name, itemID)
            if ok and type(value) == "string" then
                display = BuildItemDisplay(value, nil, nil, nil)
            end
        end
        if display then
            out[#out + 1] = { text = display, itemID = itemID }
        end
        -- 让客户端去加载这件物品，下次就能带品质颜色和链接
        if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
    end

    if #out == 0 then return nil end
    return out
end

---扫描物品表建立反查索引（每会话一次）。onDone 在扫完时调用。
---@param onDone function?
---@return boolean 是否已启动（或已经在跑）
function D:BuildItemRewardIndex(onDone)
    -- 已经确认过不可用：不再重试，也不再往诊断日志里刷同样的行
    if rewardIndex == false then return false end
    if type(rewardIndex) == "table" and not scanState then
        if onDone then pcall(onDone) end
        return true
    end
    if scanState then return true end

    local itemDB = itemEntity()
    if not itemDB or type(itemDB.GetAllIds) ~= "function" or type(itemDB.questRewards) ~= "function" then
        rewardIndex = false
        -- 分两种：完全没装 QuestieDB 插件（正常，绝大多数用户如此）与装了但接口对不上（真异常）
        if not itemDB then
            QCT.Log:Add("rewards", "未安装 QuestieDB 独立插件，跳过物品反查（正常，不影响任务链与奖励金额）")
        else
            QCT.Log:Add("rewards", "物品表反查不可用 | 实体:",
                type(itemDB), "| GetAllIds:", type(itemDB and itemDB.GetAllIds),
                "| questRewards:", type(itemDB and itemDB.questRewards))
        end
        return false
    end

    local ok, ids = pcall(itemDB.GetAllIds)
    if not ok or type(ids) ~= "table" or #ids == 0 then
        QCT.Log:Add("rewards", "物品表反查失败 | GetAllIds ->", ok and ("表:" .. #(ids or {})) or tostring(ids))
        return false
    end

    rewardIndex = {}
    scanState = { ids = ids, cursor = 1, total = #ids, links = 0, quests = 0 }
    QCT.Log:Add("rewards", "开始扫描物品表 | 物品:", scanState.total)

    local state = scanState
    local index = rewardIndex

    local function step()
        local from = state.cursor
        local to = from + SCAN_BATCH - 1
        if to > state.total then to = state.total end

        for i = from, to do
            local rok, questIds = pcall(itemDB.questRewards, state.ids[i])
            if rok and type(questIds) == "table" then
                for _, questId in ipairs(questIds) do
                    if type(questId) == "number" and questId > 0 then
                        local list = index[questId]
                        if not list then
                            list = {}
                            index[questId] = list
                            state.quests = state.quests + 1
                        end
                        list[#list + 1] = state.ids[i]
                        state.links = state.links + 1
                    end
                end
            end
        end

        state.cursor = to + 1
        if state.cursor > state.total then
            scanState = nil
            QCT.Log:Add("rewards", "物品表扫描完成 | 物品:", state.total,
                "| 有物品奖励的任务:", state.quests, "| 关联:", state.links)
            if onDone then pcall(onDone) end
            return true
        end
        return false
    end

    if C_Timer and C_Timer.NewTicker then
        local ticker
        ticker = C_Timer.NewTicker(SCAN_INTERVAL, function()
            local done = step()
            if done and ticker then pcall(ticker.Cancel, ticker) end
        end)
    elseif C_Timer and C_Timer.After then
        local function loop()
            if not step() then C_Timer.After(SCAN_INTERVAL, loop) end
        end
        C_Timer.After(SCAN_INTERVAL, loop)
    else
        step()
    end

    return true
end

---@return table[] rewards 每项 { faction = string, value = number }
function D:GetReputationReward(questId)
    local quest = self:GetQuest(questId)
    if not quest or type(quest.reputationReward) ~= "table" then return {} end

    local out = {}
    for _, pair in ipairs(quest.reputationReward) do
        local factionId, value = pair[1], pair[2]
        if factionId and value then
            local factionName
            if mod.QuestieReputation and type(mod.QuestieReputation.GetFactionName) == "function" then
                local ok, name = pcall(mod.QuestieReputation.GetFactionName, factionId)
                if ok then factionName = name end
            end
            if not factionName and C_Reputation and C_Reputation.GetFactionDataByID then
                local ok, data = pcall(C_Reputation.GetFactionDataByID, factionId)
                if ok and type(data) == "table" then factionName = data.name end
            end
            if factionName then
                out[#out + 1] = { faction = factionName, value = value }
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- 任务详情：接取/交付地点、区域、任务标签（精英/副本）、完成条件
--------------------------------------------------------------------------------

local TAG_TEXT = {
    [1] = "精英",
    [21] = "职业任务",
    [41] = "PvP",
    [62] = "团队副本",
    [81] = "副本",
    [82] = "世界事件",
    [83] = "传说",
    [84] = "护送",
    [85] = "英雄",
    [88] = "团队副本",
    [89] = "团队副本",
    [98] = "场景",
    [102] = "账号",
    [294] = "天庭",
}

local DUNGEON_TAGS = { [62] = true, [81] = true, [88] = true, [89] = true }

---区域 ID -> 区域名
local function ZoneName(zoneId)
    local id = tonumber(zoneId)
    if not id or id <= 0 then return nil end

    if C_Map and type(C_Map.GetAreaInfo) == "function" then
        local ok, name = pcall(C_Map.GetAreaInfo, id)
        if ok then
            local safe = SafeString(name)
            if safe and safe ~= "" then return safe end
        end
    end
    if type(GetRealZoneText) == "function" then
        local ok, name = pcall(GetRealZoneText, id)
        if ok then
            local safe = SafeString(name)
            if safe and safe ~= "" then return safe end
        end
    end
    return nil
end

---从 id 列表里取第一个有效 id（兼容数组和 set 两种写法）
local function FirstId(list)
    if type(list) ~= "table" then return nil end
    for _, value in ipairs(list) do
        if type(value) == "number" and value > 0 then return value end
    end
    for key, value in pairs(list) do
        if type(key) == "number" and key > 1 and value then return key end
    end
    return nil
end

---Questie 的 NPC 实体（name / zoneID / subName）
function D:GetNPC(npcId)
    if not npcId then return nil end

    local QDB = mod.QuestieDB
    if QDB and type(QDB.GetNPC) == "function" then
        local ok, npc = pcall(QDB.GetNPC, QDB, npcId)
        if ok and type(npc) == "table" then return npc end
    end

    local entity = mod.DB and mod.DB.Npc
    if entity and type(entity.name) == "function" then
        local ok, name = pcall(entity.name, npcId)
        if ok and type(name) == "string" then
            local zoneOk, zone = pcall(entity.zoneID, npcId)
            return { id = npcId, name = name, zoneID = zoneOk and zone or nil }
        end
    end
    return nil
end

---Questie 的 GameObject 实体
function D:GetObject(objectId)
    if not objectId then return nil end

    local QDB = mod.QuestieDB
    if QDB and type(QDB.GetObject) == "function" then
        local ok, object = pcall(QDB.GetObject, QDB, objectId)
        if ok and type(object) == "table" then return object end
    end

    local entity = mod.DB and mod.DB.Object
    if entity and type(entity.name) == "function" then
        local ok, name = pcall(entity.name, objectId)
        if ok and type(name) == "string" then
            local zoneOk, zone = pcall(entity.zoneID, objectId)
            return { id = objectId, name = name, zoneID = zoneOk and zone or nil }
        end
    end
    return nil
end

---任务标签：返回 tagId, 中文标签, 是否副本/团本
function D:GetQuestTag(questId)
    local tagId

    local QDB = mod.QuestieDB
    if QDB and type(QDB.GetQuestTagInfo) == "function" then
        local ok, id = pcall(QDB.GetQuestTagInfo, questId)
        if ok and type(id) == "number" then tagId = id end
    end

    if not tagId and C_QuestLog and type(C_QuestLog.GetQuestTagInfo) == "function" then
        local ok, info = pcall(C_QuestLog.GetQuestTagInfo, questId)
        if ok and type(info) == "table" then
            local idOk, id = pcall(function() return info.tagID end)
            if idOk and type(id) == "number" then tagId = id end
        end
    end

    if not tagId then return nil, nil, false end
    return tagId, TAG_TEXT[tagId], DUNGEON_TAGS[tagId] == true
end

---@return string? name, string? zone, string? kind
function D:GetStartPlace(questId)
    local quest = self:GetQuest(questId)
    if not quest then return nil end

    local zone = ZoneName(quest.zoneOrSort)
    local startedBy = quest.startedBy

    local npcId = FirstId(startedBy and startedBy[1])
    if npcId then
        local npc = self:GetNPC(npcId)
        if npc then
            return SafeString(npc.name) or ("NPC " .. npcId), ZoneName(npc.zoneID) or zone, "npc"
        end
    end

    local objectId = FirstId(startedBy and startedBy[2])
    if objectId then
        local object = self:GetObject(objectId)
        if object then
            return SafeString(object.name) or ("物体 " .. objectId), ZoneName(object.zoneID) or zone, "object"
        end
    end

    local itemId = FirstId(startedBy and startedBy[3])
    if itemId then
        local itemName = SafeString(select(1, ItemInfo(itemId)))
        return itemName or ("物品 " .. itemId), zone, "item"
    end

    return nil, zone, nil
end

---@return string? name, string? zone, string? kind
function D:GetEndPlace(questId)
    local quest = self:GetQuest(questId)
    if not quest then return nil end

    local zone = ZoneName(quest.zoneOrSort)
    local finishedBy = quest.finishedBy

    local npcId = FirstId(finishedBy and finishedBy[1])
    if npcId then
        local npc = self:GetNPC(npcId)
        if npc then
            return SafeString(npc.name) or ("NPC " .. npcId), ZoneName(npc.zoneID) or zone, "npc"
        end
    end

    local objectId = FirstId(finishedBy and finishedBy[2])
    if objectId then
        local object = self:GetObject(objectId)
        if object then
            return SafeString(object.name) or ("物体 " .. objectId), ZoneName(object.zoneID) or zone, "object"
        end
    end

    return nil, zone, nil
end

---完成条件（带进度的原生文本优先）
---@return string[]
function D:GetObjectiveLines(questId)
    local out = {}

    if self:IsInLog(questId) and C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function" then
        local ok, text = pcall(C_QuestLog.GetQuestObjectives, questId)
        if ok then
            local safe = SafeString(text)
            if safe then
                for rawLine in safe:gmatch("[^\r\n]+") do
                    local trimmed = rawLine:gsub("^%s+", ""):gsub("%s+$", "")
                    if trimmed ~= "" then out[#out + 1] = trimmed end
                end
                if #out > 0 then return out end
            end
        end
    end

    local quest = self:GetQuest(questId)
    if quest then
        for _, objective in ipairs(quest.ObjectiveData or {}) do
            local text = SafeString(objective.Text)
            if text and text ~= "" then out[#out + 1] = text end
        end
    end
    return out
end

---一次取齐某个任务在详情窗里要展示的所有东西
function D:GetQuestDetail(questId)
    local quest = self:GetQuest(questId)
    if not quest then return nil end

    local detail = {
        id = questId,
        name = self:GetName(questId) or ("任务 " .. tostring(questId)),
        level = self:GetLevel(questId),
        state = self:GetState(questId),
        zone = ZoneName(quest.zoneOrSort),
    }

    local tagId, tagText, isDungeon = self:GetQuestTag(questId)
    detail.tagId = tagId
    detail.tagText = tagText
    detail.isDungeon = isDungeon

    detail.startName, detail.startZone = self:GetStartPlace(questId)
    detail.endName, detail.endZone = self:GetEndPlace(questId)

    detail.description = self:GetDescription(questId)
    detail.objectives = self:GetObjectiveLines(questId)

    detail.xp = self:GetXP(questId)
    detail.money = self:GetMoney(questId)
    detail.items = self:GetRewardItems(questId)
    detail.reputations = self:GetReputationReward(questId)

    return detail
end

---完整任务链：前置（递归向上）+ 当前 + 后续（递归向下）
---@return table[] entries 每项 { id = number, kind = "prereq"|"current"|"next" }
function D:BuildFullChain(questId, maxDepth)
    maxDepth = maxDepth or 30

    local seen = { [questId] = true }
    local before = {}

    local function addIds(list, out)
        if type(list) ~= "table" then return end
        for _, value in ipairs(list) do
            if type(value) == "number" and value > 0 then out[#out + 1] = value end
        end
    end

    local function walkUp(id, depth)
        if depth > maxDepth then return end
        local quest = self:GetQuest(id)
        if not quest then return end

        local parents = {}
        addIds(quest.preQuestSingle, parents)
        addIds(quest.preQuestGroup, parents)
        addIds(quest.breadcrumbs, parents)
        addIds(quest.breacrumbs, parents)

        for _, parentId in ipairs(parents) do
            if not seen[parentId] then
                seen[parentId] = true
                walkUp(parentId, depth + 1)
                before[#before + 1] = parentId
            end
        end
    end

    walkUp(questId, 0)

    local after, truncated = self:BuildChain(questId, maxDepth)

    local list = {}
    for _, id in ipairs(before) do list[#list + 1] = { id = id, kind = "prereq" } end
    list[#list + 1] = { id = questId, kind = "current" }
    for _, id in ipairs(after) do list[#list + 1] = { id = id, kind = "next" } end
    return list, truncated
end

--------------------------------------------------------------------------------
-- 任务日志
--------------------------------------------------------------------------------

---取第 index 条任务日志的 (questId, title, isHeader)。
---注意：这个客户端的 title 可能是 secret value，读出来一处理就抛错，
---所以这里只信任数字型的 questID，标题一律 pcall 兜住，取不到就当没有。
local function questIdFromIndex(index)
    if C_QuestLog and type(C_QuestLog.GetInfo) == "function" then
        local ok, info = pcall(C_QuestLog.GetInfo, index)
        if ok and type(info) == "table" then
            local id
            local idOk, value = pcall(function() return info.questID end)
            if idOk then
                local numOk, num = pcall(tonumber, value)
                if numOk and type(num) == "number" and num > 0 then id = num end
            end

            local title, isHeader
            local titleOk, value2 = pcall(function() return info.title end)
            if titleOk and type(value2) == "string" then
                local textOk, text = pcall(string.format, "%s", value2)
                if textOk then title = text end
            end
            local headerOk, header = pcall(function() return info.isHeader end)
            if headerOk then isHeader = header end

            if id then return id, title, isHeader end
        end
    end

    if GetQuestLogTitle then
        local ok, title, _, _, isHeader, _, _, _, questId = pcall(GetQuestLogTitle, index)
        if ok then
            local numOk, num = pcall(tonumber, questId)
            if numOk and type(num) == "number" and num > 0 then
                local safeTitle
                if type(title) == "string" then
                    local textOk, text = pcall(string.format, "%s", title)
                    if textOk then safeTitle = text end
                end
                return num, safeTitle, isHeader
            end
        end
    end

    -- 兜底：任务日志里 shift+点击能把任务链接贴到聊天框，说明客户端给得出这个字符串。
    -- 从 "|Hquest:1234:21|h..." 里抠 ID，比标题反查可靠得多
    -- （这个客户端的标题是 secret value，读出来一比较就抛错）。
    if type(GetQuestLink) == "function" then
        local ok, link = pcall(GetQuestLink, index)
        if ok and type(link) == "string" then
            local mok, num = pcall(string.match, link, "quest:(%d+)")
            if mok and num then
                local value = tonumber(num)
                if value and value > 0 then return value, nil, nil end
            end
        end
    end
    return nil
end

---按任务日志索引取任务 ID（对外用冒号调用，所以这里必须是方法形式）
function D:GetQuestIdByIndex(index)
    return questIdFromIndex(index)
end

function D:RefreshQuestLog()
    local byTitle, byId, byIndex, titleById = {}, {}, {}, {}
    local count = 0

    if C_QuestLog and type(C_QuestLog.GetNumQuestLogEntries) == "function" then
        local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and type(n) == "number" then count = n end
    end
    if count == 0 and type(GetNumQuestLogEntries) == "function" then
        local ok, n = pcall(GetNumQuestLogEntries)
        if ok and type(n) == "number" then count = n end
    end

    local entries, headerCount, failed = 0, 0, 0
    for index = 1, count do
        -- 单条出问题不能拖垮整张表，更不能让启动流程中断
        local ok, questId, title, isHeader = pcall(questIdFromIndex, index)
        if not ok then
            failed = failed + 1
        elseif isHeader then
            headerCount = headerCount + 1
        elseif questId and questId > 0 then
            byId[questId] = true
            byIndex[questId] = index
            entries = entries + 1
            if title then
                titleById[questId] = title
                local keyOk, key = pcall(F.NormalizeTitle, title)
                if keyOk and key then
                    byTitle[key] = byTitle[key] or questId
                end
            end
        end
    end

    self.logByTitle = byTitle
    self.logById = byId
    self.logIndexById = byIndex
    self.logTitleById = titleById
    self.logCount = entries
    self.stateCache = {}
    F.ClearWrapCache()
    QCT:Trace("questlog", "刷新 | 条目:", entries, "| 标题:", headerCount, "| 失败:", failed)
end

---这件物品**能开启**哪个任务（QuestieDB 物品表的 startQuest 字段）。
---@param itemId number?
---@return number? questId
function D:GetQuestStartedByItem(itemId)
    if type(itemId) ~= "number" or itemId <= 0 then return nil end
    local entity = itemEntity()
    if not entity or type(entity.startQuest) ~= "function" then return nil end
    local ok, questId = pcall(entity.startQuest, itemId)
    if ok and type(questId) == "number" and questId > 0 then return questId end
    return nil
end

---在玩家任务日志里找「目标文本里提到这个物品名」的任务。
---
---为什么要这条：本服有大量自定义物品（物品 ID 都是 27 万这种），
---QuestieDB 是原版数据，对它们没有 startQuest 记录 —— 玩家实测
---「注入巫毒的神器」就是这种情况（物品认出来了，但查不到任务）。
---日志里的任务目标文本是客户端给的，自定义任务也照样有，按物品名匹配最实际。
---@param itemName string?
---@return number? questId
function D:FindLogQuestByItemName(itemName)
    if type(itemName) ~= "string" or itemName == "" then return nil end
    if not self.logById then self:RefreshQuestLog() end

    for questId in pairs(self.logById or {}) do
        local quest = self:GetQuest(questId)
        if quest then
            for _, text in ipairs({ quest.objectivesText, quest.Description }) do
                -- 有的数据源给的是多行表，先拼起来再找
                if type(text) == "table" then
                    local okJoin, joined = pcall(table.concat, text, "\n")
                    if okJoin then text = joined end
                end
                if type(text) == "string" and text ~= "" then
                    local ok, found = pcall(string.find, text, itemName, 1, true)
                    if ok and found then return questId end
                end
            end
        end
    end
    return nil
end

---这件物品对应哪个任务。三条路，从准到宽：
---  1) QuestieDB 的 startQuest（标准物品，最准）
---  2) QuestieDB 的 relatedQuests（相关任务，退一步）
---  3) 任务日志里目标文本提到这件物品名（自定义物品只能走这条）
---@param itemId number?
---@param itemName string? 提示框里拿到的物品名，没有就用 DB 里的
---@return number? questId, string? source
function D:GetQuestForItem(itemId, itemName)
    if type(itemId) ~= "number" or itemId <= 0 then return nil, nil end

    local entity = itemEntity()
    if entity then
        if type(entity.startQuest) == "function" then
            local ok, questId = pcall(entity.startQuest, itemId)
            if ok and type(questId) == "number" and questId > 0 then
                return questId, "QuestieDB startQuest"
            end
        end
        if type(entity.relatedQuests) == "function" then
            local ok, list = pcall(entity.relatedQuests, itemId)
            if ok and type(list) == "table" and list[1] then
                local questId = tonumber(list[1])
                if questId and questId > 0 then return questId, "QuestieDB relatedQuests" end
            end
        end
    end

    if not itemName and entity and type(entity.name) == "function" then
        local ok, name = pcall(entity.name, itemId)
        if ok and type(name) == "string" then itemName = name end
    end
    local questId = self:FindLogQuestByItemName(itemName)
    if questId then return questId, "任务日志目标文本" end

    return nil, nil
end

---按工具提示标题找任务（只匹配任务日志里的任务，避免误伤物品/NPC 提示）
---@param title string?
---@return number?
function D:FindQuestIdByTitle(title)
    local key = F.NormalizeTitle(title)
    if not key then return nil end
    if not self.logByTitle then self:RefreshQuestLog() end
    return self.logByTitle[key]
end

--------------------------------------------------------------------------------
-- 任务链
--------------------------------------------------------------------------------

---@param questId number
---@param depth number
---@return number[] chain, boolean truncated
function D:BuildChain(questId, depth)
    local chain, seen = {}, { [questId] = true }
    local current = self:GetNext(questId)
    local guard = 0
    local hidden = mod.QuestieCorrections and mod.QuestieCorrections.hiddenQuests

    while current and current > 0 and not seen[current] and #chain < depth and guard < 40 do
        guard = guard + 1
        seen[current] = true
        -- 被 Questie 隐藏的（节日/占位/无效）任务直接跳过，但仍继续往后走
        if not (hidden and hidden[current]) then
            chain[#chain + 1] = current
        end
        current = self:GetNext(current)
    end

    local truncated = current ~= nil and current > 0 and not seen[current] and #chain >= depth
    return chain, truncated
end

---@return number[] chain, boolean truncated
function D:BuildPrerequisiteChain(questId, depth)
    local chain, seen = {}, { [questId] = true }
    local single, group = self:GetPrerequisites(questId)
    local function walk(list, level)
        if level > depth then return end
        for _, id in ipairs(list) do
            if not seen[id] then
                seen[id] = true
                chain[#chain + 1] = id
                local s2, g2 = self:GetPrerequisites(id)
                walk(s2, level + 1)
                walk(g2, level + 1)
            end
        end
    end
    walk(single, 1)
    walk(group, 1)
    return chain
end

--------------------------------------------------------------------------------
-- 调试
--------------------------------------------------------------------------------

function D:DumpQuest(questId)
    local quest = self:GetQuest(questId)
    if not quest then
        QCT:Print("没有找到任务 " .. tostring(questId))
        return
    end
    QCT:Print("任务 " .. questId .. " : " .. tostring(quest.name))
    QCT:Print("  等级: " .. tostring(self:GetLevel(questId)))
    QCT:Print("  状态: " .. tostring((self:GetState(questId))))
    QCT:Print("  在日志中: " .. tostring(self:IsInLog(questId)))
    QCT:Print("  后续: " .. tostring(self:GetNext(questId)))
    QCT:Print("  经验: " .. tostring(self:GetXP(questId)) .. "  金钱: " .. tostring(self:GetMoney(questId)))
    local desc = self:GetDescription(questId)
    QCT:Print("  描述行数: " .. tostring(#desc))
    for i, line in ipairs(desc) do
        QCT:Print("    " .. i .. ": " .. line)
    end
    local chain, truncated = self:BuildChain(questId, 10)
    QCT:Print("  后续链: " .. table.concat(chain, " -> ") .. (truncated and " ..." or ""))
end
