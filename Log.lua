--[[
后台日志：插件自己把运行过程记下来，不需要用户手动开调试或输命令。

为什么要这么小心地 tostring：
这个客户端会把「外来帧（别的插件创建的帧）持有的 tooltip 文本」标记成 secret value（加密字符串），
对这类值做比较、格式化、拼接都会直接抛 Lua 错误。所以这里统一走 SafeStr，
先 pcall 再取值，取不到就记成 <secret>，绝不让日志本身把插件搞崩。

日志写在 SavedVariables（QuestChainTipDB.log），游戏退出或 /reload 时由客户端落盘，
路径：WTF/Account/<账号>/SavedVariables/QuestChainTip.lua
]]

local ADDON, ns = ...
local QCT = ns

local L = {}
QCT.Log = L

local MAX_ENTRIES = 240
local MAX_IMPORTANT = 100

-- 这些分类进「重要事件」队列：不会被大量悬停记录挤掉，排查问题先看它们
local IMPORTANT_TAGS = {
    session = true,
    start = true,
    api = true,
    rewards = true,
    error = true,
    hooks = true,
    detail = true,
}

-- 这些分类是高频噪声（鼠标每动一下就来几条），同一条内容连续重复时只留一份
local NOISY_TAGS = {
    setowner = true,
    detect = true,
    tooltip = true,
    panel = true,
    hooks = true,
    questlog = true,
    build = true,
}

local pcall, type, tostring, select, date = pcall, type, tostring, select, date

---把任意值转成可以安全写进存档的字符串
local function SafeStr(value)
    local kind = type(value)
    if value == nil then return "nil" end
    if kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    if kind == "string" then
        -- secret string 在这里会抛错，用 pcall 兜住
        local ok, text = pcall(string.format, "%s", value)
        if ok and type(text) == "string" then
            -- 去掉颜色码，日志更好读；再截断，避免超长
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "[icon]")
            if #text > 200 then text = text:sub(1, 200) .. "…" end
            return text
        end
        return "<secret>"
    end
    if kind == "table" then
        local ok, name = pcall(function() return rawget(value, "name") or rawget(value, "Id") end)
        if ok and type(name) == "number" then return "<table:" .. name .. ">" end
        return "<table>"
    end
    return "<" .. kind .. ">"
end
L.SafeStr = SafeStr

function L:Init()
    if self.ready then return end
    self.ready = true
    self.entries = {}
    self.important = {}
    self.lastNoisy = {}

    local db = QCT.db
    if not db then return end

    -- 沿用上次的日志（滚动保留），并在开头打一条会话分隔
    if type(db.log) == "table" then
        for _, line in ipairs(db.log) do
            if type(line) == "string" then
                self.entries[#self.entries + 1] = line
            end
        end
    end
    db.log = self.entries

    -- 重要事件单独恢复：普通队列会被悬停噪声滚掉，这里不会
    if type(db.logImportant) == "table" then
        for _, line in ipairs(db.logImportant) do
            if type(line) == "string" then
                self.important[#self.important + 1] = line
            end
        end
    end
    db.logImportant = self.important

    self:Add("session", "================ 新的会话 ================")
end

---滚动裁剪（Lua 5.1 没有 table.move，手写搬移）
local function Trim(list, maxEntries)
    local overflow = #list - maxEntries
    if overflow <= 0 then return list end
    local kept = {}
    for index = overflow + 1, #list do
        kept[#kept + 1] = list[index]
    end
    return kept
end

---记一条日志。tag 是分类，后面可以跟任意多个值。
function L:Add(tag, ...)
    local tagText = SafeStr(tag)
    local parts = {}
    local count = select("#", ...)
    for index = 1, count do
        parts[index] = SafeStr((select(index, ...)))
    end

    local message = table.concat(parts, " ")
    local stamp = "?"
    local ok, value = pcall(date, "%H:%M:%S")
    if ok and type(value) == "string" then stamp = value end

    local line = stamp .. " [" .. tagText .. "] " .. message

    -- 噪声降噪：同一分类、同一内容连续重复时只记一次（避免 240 条一分钟被刷满）
    if NOISY_TAGS[tagText] then
        local last = self.lastNoisy and self.lastNoisy[tagText]
        if last == message then
            return line
        end
        self.lastNoisy = self.lastNoisy or {}
        self.lastNoisy[tagText] = message
    end

    local entries = self.entries
    if not entries then
        entries = {}
        self.entries = entries
    end
    entries[#entries + 1] = line
    self.entries = Trim(entries, MAX_ENTRIES)
    if QCT.db then QCT.db.log = self.entries end

    -- 重要事件同时进独立队列，永不被悬停噪声挤出
    if IMPORTANT_TAGS[tagText] then
        local important = self.important
        if not important then
            important = {}
            self.important = important
        end
        important[#important + 1] = line
        self.important = Trim(important, MAX_IMPORTANT)
        if QCT.db then QCT.db.logImportant = self.important end
    end

    return line
end

---把最近若干条打到聊天框（只在用户主动想看时调用）
function L:Print(count)
    count = count or 25

    local important = self.important or {}
    if #important > 0 then
        local fromImp = math.max(1, #important - count + 1)
        QCT:Print("---- 重要事件 " .. (#important - fromImp + 1) .. " 条 ----")
        for index = fromImp, #important do
            QCT:Print(important[index])
        end
    end

    local entries = self.entries or {}
    local from = math.max(1, #entries - count + 1)
    QCT:Print("---- 最近 " .. (#entries - from + 1) .. " 条日志 ----")
    for index = from, #entries do
        QCT:Print(entries[index])
    end
    QCT:Print("完整日志已写入 WTF/.../SavedVariables/QuestChainTip.lua（/reload 后落盘）")
end

function L:Clear()
    self.entries = {}
    self.important = {}
    self.lastNoisy = {}
    if QCT.db then
        QCT.db.log = self.entries
        QCT.db.logImportant = self.important
    end
    self:Add("session", "日志已清空")
end
