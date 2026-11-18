--[[
QuestChainTip / 任务链提示
为"已经接取、正在做"的任务补全：任务描述、任务奖励、后续任务链。
数据来自 Questie / QuestieDB，本插件只负责读取与展示。
]]

local ADDON, ns = ...
local QCT = ns
local L = QCT.Locale

QCT.ADDON = ADDON
QCT.VERSION = "1.0.0"

--------------------------------------------------------------------------------
-- 配置
--------------------------------------------------------------------------------

local DEFAULTS = {
    enabled = true,
    showDescription = true,
    showRewards = true,
    showChain = true,
    chainRewards = true,    -- 后续任务每行也显示经验/金钱/状态
    showPrereq = true,      -- 是否显示前置任务
    panelMode = "map",      -- 悬停面板：off=关闭 / map=仅世界地图（默认） / all=全部位置
    chainKey = "SHIFT",     -- 详情窗快捷键：SHIFT / CTRL / ALT / NONE（不启用）
    descLines = 3,          -- 悬停面板最多显示几行描述
    chainDepth = 3,         -- 悬停面板最多显示几层后续
    chainDepthShift = 20,   -- 详情窗（地图上按 Shift）最多列多少环
    rewardCache = {},       -- questId -> 物品奖励缓存（客户端接口只对已接任务有效，缓存用来补历史）
    diag = false,           -- 在聊天框里输出「为什么没开窗 / 已开窗」的诊断（排查问题时才开）
    debug = false,
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

QCT.db = {}
QCT.Defaults = DEFAULTS

-- 日志模块的占位实现：万一 Log.lua 没被加载或加载失败，调用方也不会因此报错
if not QCT.Log then
    local function noop() end
    QCT.Log = { Add = noop, Print = noop, Init = noop, Clear = noop, SafeStr = tostring }
end

--------------------------------------------------------------------------------
-- 输出
--------------------------------------------------------------------------------

local PREFIX = L["|cff33ff99任务链提示|r: "]

---@param ... any 可以传多个值，会自动 tostring 后用空格连起来
function QCT:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. table.concat(parts, " "))
end

function QCT:Debug(...)
    if not QCT.db.debug then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff808080[QCT]|r " .. table.concat(parts, " "))
end

---同时写聊天框（受 debug 开关控制）和后台日志（永远记录）
function QCT:Trace(tag, ...)
    if QCT.Log then QCT.Log:Add(tag, ...) end
    if QCT.db and QCT.db.debug then
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring((select(i, ...)))
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff808080[QCT]|r " .. table.concat(parts, " "))
    end
end

--------------------------------------------------------------------------------
-- 启动
--------------------------------------------------------------------------------

local started = false

function QCT:Start()
    if started then return true end

    -- 注意：这里不能因为 Questie 还没加载完就放弃安装钩子。
    -- Questie 的模块是在它自己的 PLAYER_LOGIN 里才建好的，谁先谁后不固定，
    -- 数据层每次取数据时都会重试，所以钩子先装上，数据晚点接上也来得及。
    local hasData = self.Data:Init()
    if not hasData and not self.warnedNoData then
        self.warnedNoData = true
        self:Trace("start", "Questie 数据源暂未就绪，钩子已安装，稍后自动接上")
    end

    -- 先把钩子装上：后面任何一步出错都不能让插件变成“完全不工作”
    self.Tooltip:Enable()

    -- 任务日志缓存失败也只是缓存没有，不能影响插件运行
    local refreshOk, refreshErr = pcall(self.Data.RefreshQuestLog, self.Data)
    if not refreshOk then
        self:Trace("start", "刷新任务日志失败:", tostring(refreshErr))
    end

    started = true
    self:Trace("start", "启动完成 | 数据源:", hasData and "就绪" or "未就绪",
        "| 日志条目:", self.Data.logCount or 0)
    self:Trace("api", "GetItemInfo:", type(GetItemInfo),
        "| C_Item.GetItemInfo:", type(_G.C_Item and _G.C_Item.GetItemInfo),
        "| GetQuestLogRewardInfo:", type(GetQuestLogRewardInfo),
        "| GetNumQuestLogRewards:", type(GetNumQuestLogRewards),
        "| GetItemQualityColor:", type(_G.GetItemQualityColor))

    -- 给 Questie 一点时间：如果几秒后还是没数据源，再提示用户，避免加载顺序造成误报
    if not hasData and C_Timer and C_Timer.After then
        C_Timer.After(6, function()
            if self.Data:Init() then
                self:Trace("start", "Questie 数据源已就绪（延迟接上）")
                local ok, err = pcall(self.Data.RefreshQuestLog, self.Data)
                if not ok then self:Trace("start", "延迟刷新失败:", tostring(err)) end
                return
            end
            self:Print(L["没有找到 Questie / QuestieDB，本插件需要它们提供任务数据，请确认 Questie 已启用。"])
            self:Print(L["输入 |cffffff00/qct why|r 可以查看详细状态。"])
        end)
    end

    -- 预热物品奖励缓存：客户端接口只对已接任务有效，趁任务还在日志里先把物品存下来，
    -- 以后这些任务交掉了、或者出现在任务链上，也能显示出物品奖励。
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            local data = self.Data
            local count, cached = 0, 0
            for questId in pairs(data.logById or {}) do
                count = count + 1
                local ok, items = pcall(data.GetRewardItems, data, questId)
                if ok and type(items) == "table" and #items > 0 then
                    cached = cached + 1
                    -- 逐条记录：这是判断「客户端到底给不给物品奖励」的一手数据
                    self:Trace("rewards", "预热 | 任务:", questId, "| 物品:", #items,
                        "| 首件:", items[1] and items[1].text or "?")
                else
                    local numOk, num = pcall(GetNumQuestLogRewards, questId)
                    self:Trace("rewards", "预热 | 任务:", questId, "| 无物品 | GetNumQuestLogRewards ->",
                        numOk and tostring(num) or "调用失败")
                end
            end
            self:Trace("rewards", "预热完成 | 任务:", count, "| 有物品奖励:", cached)
        end)
    end

    -- 后台扫一遍 QuestieDB 物品表，建立「任务 -> 奖励物品」反查表。
    -- 有了它，未接的后续任务也能显示物品奖励（客户端接口做不到这一点）。
    if C_Timer and C_Timer.After then
        local tries = 0
        local function startScan()
            tries = tries + 1
            local data = self.Data
            local started = data:BuildItemRewardIndex(function()
                -- 扫完后把已经打开的面板/窗口按新数据重画一次
                if self.Window and self.Window:IsShown() then
                    local questId = self.Window.questId
                    if questId then pcall(self.Window.Open, self.Window, questId) end
                end
            end)
            -- QuestieDB 有可能比我们更晚加载完，没启动就隔几秒再试几次
            if not started and tries < 6 then
                C_Timer.After(10, startScan)
            end
        end
        C_Timer.After(5, startScan)
    end

    return hasData
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_REMOVED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        QuestChainTipDB = QuestChainTipDB or {}
        QCT.db = CopyDefaults(DEFAULTS, QuestChainTipDB)

        -- 1.5.6：悬停面板的默认值从「关闭」改成「仅世界地图」。
        -- 老存档里存的是 "off"，光改 DEFAULTS 对老用户不生效，所以这里做一次迁移：
        -- 只迁移一次，之后玩家在设置里手动关掉就不会被改回来。
        if not QCT.db.panelModeMigrated then
            QCT.db.panelModeMigrated = true
            if QCT.db.panelMode == "off" then
                QCT.db.panelMode = "map"
            end
        end

        if QCT.Log then QCT.Log:Init() end
        return
    end

    if event == "PLAYER_LOGIN" then
        QCT:Start()
        return
    end

    if not started then
        -- 少数情况下插件晚于 PLAYER_LOGIN 加载（例如被 LoD 或其它插件延迟载入）
        if event == "PLAYER_ENTERING_WORLD" then QCT:Start() end
        return
    end

    if event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED"
        or event == "QUEST_TURNED_IN" or event == "PLAYER_ENTERING_WORLD" then
        local ok, err = pcall(QCT.Data.RefreshQuestLog, QCT.Data)
        if not ok then QCT:Trace("event", event, "刷新失败:", tostring(err)) end
        QCT.Data:InvalidateCache()
        -- 任务日志的标题按钮是打开界面时才创建的，补挂一次钩子
        local hookOk, hookErr = pcall(QCT.Tooltip.InstallQuestLogHooks, QCT.Tooltip)
        if not hookOk then QCT:Trace("event", event, "补挂钩子失败:", tostring(hookErr)) end
    end
end)

--------------------------------------------------------------------------------
-- 斜杠命令
--------------------------------------------------------------------------------

local function PrintHelp()
    QCT:Print(L["命令:"])
    QCT:Print(L["  |cffffff00/qct|r - 打开设置界面"])
    QCT:Print(L["  |cffffff00/qct on|off|r - 启用/关闭"])
    QCT:Print(L["  |cffffff00/qct desc|reward|chain|reward2|prereq|r - 分项开关"])
    QCT:Print(L.F("  |cffffff00/qct depth <n>|r - 普通状态下后续任务层数 (当前 %d)", QCT.db.chainDepth))
    QCT:Print(L.F("  |cffffff00/qct depthshift <n>|r - 详情窗最多环数 (当前 %d)", QCT.db.chainDepthShift))
    QCT:Print(L["  |cffffff00/qct debug|r - 调试输出"])
    QCT:Print(L["  |cffffff00/qct explain|r - 聊天框诊断信息（为什么没开窗，默认关）"])
    QCT:Print(L["  |cffffff00/qct log|r - 列出当前任务日志的识别结果"])
    QCT:Print(L["  |cffffff00/qct dump <任务ID>|r - 打印某任务解析结果"])
    QCT:Print(L["  |cffffff00/qct test|r - 强制画一个测试面板（检查显示是否正常）"])
    QCT:Print(L["  |cffffff00/qct detail <任务ID>|r - 打开任务链详情窗（等价于在地图上按快捷键）"])
    QCT:Print(L["  |cffffff00/qct rewards <任务ID>|r - 探测该任务的奖励接口，结果写入日志"])
    QCT:Print(L["  |cffffff00/qct why|r - 打印运行状态，排查为什么没显示"])
    QCT:Print(L["  |cffffff00/qct trace|r - 打印后台日志（默认一直在记，无需开启）"])
    QCT:Print(L["  |cffffff00/qct locale <zhCN|zhTW|enUS|auto>|r - 切换界面语言"])
    QCT:Print(L["  |cffffff00/qct key <shift|ctrl|alt|none>|r - 详情窗快捷键（默认 shift，可避开 Questie 的 Shift）"])
end

SLASH_QUESTCHAINTIP1 = "/qct"
SLASH_QUESTCHAINTIP2 = "/questchaintip"
SlashCmdList["QUESTCHAINTIP"] = function(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = input:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "config" or cmd == "options" then
        if QCT.Options then
            QCT.Options:Open()
        else
            QCT:Print(L["设置界面未加载"])
        end
    elseif cmd == "locale" then
        local want = (rest or ""):gsub("%s+", "")
        local now = L.SetLocale(want ~= "" and want or "auto")
        QCT:Print(L.F("界面语言已切换为 %s（/reload 后完全生效）", now))
    elseif cmd == "key" then
        -- 详情窗快捷键。Questie 也用 Shift，玩家可以改成 Ctrl / Alt 或直接关掉
        local want = (rest or ""):gsub("%s+", ""):upper()
        if want == "SHIFT" or want == "CTRL" or want == "ALT" or want == "NONE" then
            QCT.db.chainKey = want
            local label = (QCT.Tooltip and QCT.Tooltip.ChainKeyLabel and QCT.Tooltip.ChainKeyLabel()) or want
            QCT:Print(L.F("详情窗快捷键: %s", label))
        else
            QCT:Print(L["用法: /qct key shift|ctrl|alt|none"])
        end
    elseif cmd == "toggle" then
        QCT.db.enabled = not QCT.db.enabled
        QCT:Print(L.F("插件已%s", L[QCT.db.enabled and "|cff00ff00开启|r" or "|cffff0000关闭|r"]))
    elseif cmd == "on" then
        QCT.db.enabled = true
        QCT:Print(L.F("插件已%s", L["|cff00ff00开启|r"]))
    elseif cmd == "off" then
        QCT.db.enabled = false
        QCT:Print(L.F("插件已%s", L["|cffff0000关闭|r"]))
    elseif cmd == "desc" then
        QCT.db.showDescription = not QCT.db.showDescription
        QCT:Print(L.F("任务描述: %s", L[QCT.db.showDescription and "开" or "关"]))
    elseif cmd == "reward" then
        QCT.db.showRewards = not QCT.db.showRewards
        QCT:Print(L.F("任务奖励: %s", L[QCT.db.showRewards and "开" or "关"]))
    elseif cmd == "chain" then
        QCT.db.showChain = not QCT.db.showChain
        QCT:Print(L.F("后续任务链: %s", L[QCT.db.showChain and "开" or "关"]))
    elseif cmd == "reward2" then
        QCT.db.chainRewards = not QCT.db.chainRewards
        QCT:Print(L.F("后续任务奖励行: %s", L[QCT.db.chainRewards and "开" or "关"]))
    elseif cmd == "prereq" then
        QCT.db.showPrereq = not QCT.db.showPrereq
        QCT:Print(L.F("前置任务: %s", L[QCT.db.showPrereq and "开" or "关"]))
    elseif cmd == "depthshift" then
        local n = tonumber(rest)
        if n and n > 0 and n <= 20 then
            QCT.db.chainDepthShift = math.floor(n)
            QCT:Print(L.F("详情窗最多环数: %d", QCT.db.chainDepthShift))
        else
            QCT:Print(L["请输入 1-20 的数字"])
        end
    elseif cmd == "depth" then
        local n = tonumber(rest)
        if n and n > 0 and n <= 20 then
            QCT.db.chainDepth = math.floor(n)
            QCT:Print(L.F("普通状态后续任务层数: %d", QCT.db.chainDepth))
        else
            QCT:Print(L["请输入 1-20 的数字"])
        end
    elseif cmd == "debug" then
        QCT.db.debug = not QCT.db.debug
        QCT:Print(L.F("调试输出: %s", L[QCT.db.debug and "开" or "关"]))
    elseif cmd == "explain" then
        QCT.db.diag = not QCT.db.diag
        QCT:Print(L.F("聊天框诊断信息: %s", L[QCT.db.diag and "开" or "关"]))
    elseif cmd == "log" then
        local data = QCT.Data
        QCT:Print(L.F("任务日志条目: %d", data.logCount or 0))
        local count = 0
        for title, id in pairs(data.logByTitle or {}) do
            count = count + 1
            if count > 40 then break end
            QCT:Print("  " .. title .. "  ->  " .. tostring(id))
        end
    elseif cmd == "trace" then
        if QCT.Log then QCT.Log:Print(tonumber(rest) or 30) end
    elseif cmd == "traceclear" then
        if QCT.Log then
            QCT.Log:Clear()
            QCT:Print(L["日志已清空"])
        end
    elseif cmd == "rewards" then
        local id = tonumber(rest)
        if id then
            QCT.Data:ProbeRewardAPI(id, true)
            QCT:Print(L.F("已探测任务 %d 的奖励接口，结果写入日志。输入 |cffffff00/qct trace 12|r 查看。", id))
        else
            QCT:Print(L["用法: /qct rewards <任务ID>"])
        end
    elseif cmd == "detail" then
        local id = tonumber(rest)
        if not id then
            local tip = QCT.Tooltip
            local state = tip and tip.state
            id = (state and state.questId) or (tip and tip.lastQuestId)
        end
        if id and QCT.Window then
            QCT.Window:Open(id)
        else
            QCT:Print(L["用法: /qct detail <任务ID>（或者把鼠标悬停在任务上再输入）"])
        end
    elseif cmd == "test" then
        if QCT.Tooltip then
            QCT.Tooltip:SelfTest()
        end
    elseif cmd == "why" or cmd == "diag" then
        if QCT.Tooltip then
            QCT.Tooltip:Diagnose()
        end
    elseif cmd == "dump" then
        local id = tonumber(rest)
        if not id then
            QCT:Print(L["用法: /qct dump <任务ID>"])
        else
            QCT.Data:DumpQuest(id)
        end
    else
        PrintHelp()
    end
end
