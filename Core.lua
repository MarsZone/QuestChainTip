--[[
QuestChainTip / 任务链提示
为"已经接取、正在做"的任务补全：任务描述、任务奖励、后续任务链。
数据来自 Questie / QuestieDB，本插件只负责读取与展示。
]]

local ADDON, ns = ...
local QCT = ns
local L = QCT.Locale

QCT.ADDON = ADDON

---版本号：直接读 toc 里的 ## Version。
---原来这里写死 "1.0.0"，从来没跟着发版改过，玩家问「我装的是哪个版本」根本答不上来。
---读 toc 就只维护一处，不会忘。
local function AddonVersion()
    local name = ADDON or "QuestChainTip"

    if type(GetAddOnMetadata) == "function" then
        local ok, value = pcall(GetAddOnMetadata, name, "Version")
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, name, "Version")
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return "?"
end
QCT.VERSION = AddonVersion()

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
    -- 地图图标上收掉 Questie 的提示框，只显示我们自己的面板（默认开，1.5.42 起）。
    -- 前提条件：我们自己的面板必须画出来了，才允许按掉它的框（见 Tooltip 里的 oursShown 判断）。
    hideQuestieTip = true,
    panelMode = "map",      -- 悬停面板：off=关闭 / map=仅世界地图（默认） / all=全部位置
    chainKey = "SHIFT",     -- 详情窗快捷键（世界地图）：SHIFT / CTRL / ALT / NONE / 任意键
    questLogKey = "ALT",    -- 任务日志快捷键：ALT / CTRL / NONE（Shift 留给原生的链接到聊天框）
    panelWidth = 380,       -- 悬停面板文本列宽（像素，240~560）
    windowWidth = "AUTO",   -- 详情窗宽度："AUTO"（按屏幕）或 420~900 的像素值
    showHealth = false,     -- 在目标/焦点框体血条上显示「当前 / 最大」（默认关）
    healthFloat = false,    -- 自由摆放：自己画一个可拖动的文字框（目标框是客户端自绘时用）
    minimap = true,         -- 显示小地图按钮
    minimapAngle = 220,     -- 小地图按钮角度（度，从 12 点顺时针）
    descLines = 3,          -- 悬停面板最多显示几行描述
    chainDepth = 3,         -- 悬停面板最多显示几层后续
    chainDepthShift = 20,   -- 详情窗（地图上按 Shift）最多列多少环
    rewardCache = {},       -- questId -> 物品奖励缓存（客户端接口只对已接任务有效，缓存用来补历史）
    diag = false,           -- 在聊天框里输出「为什么没开窗 / 已开窗」的诊断（排查问题时才开）
    muted = false,          -- 静音：完全不画面板、不开详情窗（用来确认某个弹窗是不是本插件弹的）
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

---把任意值变成「能安全塞进字符串」的东西。
---
---这个坑踩了很久，记在这里：客户端把一部分返回值（tooltip 文本、单位血量…）标成
---secret value。对它调用 tostring() **不会报错**，而是把 secret 原样返回，
---真正抛错的是之后的 table.concat / `..` / string.format。
---
---探针必须用「真正会触发 secret 检查」的操作。**踩过的坑**：一开始用 `text .. ""`
---当探针，结果这个客户端把「拼空串」当恒等运算放过了 —— 探针通过、secret 被当普通
---字符串返回，最后在 table.concat 那里炸（`Core.lua:107: invalid value (secret) at index 5`）。
---现在同时用 `.. "x"`、string.format、string.len 三道，任一抛错就判定为 secret。
local function SafeText(value)
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
QCT.SafeText = SafeText

---@param ... any 可以传多个值，会自动转成字符串后用空格连起来
function QCT:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = SafeText((select(i, ...)))
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. table.concat(parts, " "))
end

function QCT:Debug(...)
    if not QCT.db.debug then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = SafeText((select(i, ...)))
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff808080[QCT]|r " .. table.concat(parts, " "))
end

---同时写聊天框（受 debug 开关控制）和后台日志（永远记录）
function QCT:Trace(tag, ...)
    if QCT.Log then QCT.Log:Add(tag, ...) end
    if QCT.db and QCT.db.debug then
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = SafeText((select(i, ...)))
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

    -- 静音时提醒一句，免得玩家以为插件坏了
    if self.db and self.db.muted then
        self:Print("插件处于|cffffff00静音|r状态：面板和详情窗都不会画。恢复：/qct mute off")
    end

    -- 先把钩子装上：后面任何一步出错都不能让插件变成“完全不工作”
    self.Tooltip:Enable()

    -- 血量数字 / 小地图按钮：都是可选小功能，单独包一层，坏了不影响任务链主流程
    if self.Health and self.Health.Init then
        local ok, err = pcall(self.Health.Init, self.Health)
        if not ok then self:Trace("start", "血量模块初始化失败:", tostring(err)) end
    end
    if self.Minimap and self.Minimap.Init then
        local ok, err = pcall(self.Minimap.Init, self.Minimap)
        if not ok then self:Trace("start", "小地图按钮初始化失败:", tostring(err)) end
    end

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
        -- 1.5.36：1.5.35 那个「Shift 自动改成 Alt」的迁移撤掉了 —— 作者的 Shift 不能动。
        -- 已经跑过迁移的存档要改回来（只改这一次，之后玩家自己的选择不动）。
        if QCT.db.gestureAltMigrated and not QCT.db.gestureReverted then
            QCT.db.gestureReverted = true
            if QCT.db.chainKey == "ALT" and QCT.db.questLogKey == "ALT" then
                QCT.db.chainKey = "SHIFT"
            end
        end

        if not QCT.db.panelModeMigrated then
            QCT.db.panelModeMigrated = true
            if QCT.db.panelMode == "off" then
                QCT.db.panelMode = "map"
            end
        end

        -- 静音只是排查开关，不跨会话保留：免得哪天忘了关，以为插件坏了
        QCT.db.muted = false

        -- 1.5.37 把 hideQuestieTip 默认设成 true 并存进了存档；1.5.39 改回默认 false
        -- 但对老存档不生效（键已存在）。这里强制复位一次：那个功能在你的客户端上还没通，
        -- 留着 true 会一直把 Questie 的提示框吞掉。
        if not QCT.db.hideQuestieTipReverted then
            QCT.db.hideQuestieTipReverted = true
            QCT.db.hideQuestieTip = false
        end

        -- 1.5.42：判据修好之后这个功能能用了，再拨回「开」一次。
        -- 只拨一次：之后玩家自己在设置里关掉就不会被改回来。
        if not QCT.db.hideQuestieTipOn then
            QCT.db.hideQuestieTipOn = true
            QCT.db.hideQuestieTip = true
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
    QCT:Print(L["  |cffffff00/qct key <shift|ctrl|alt|none|任意键>|r - 详情窗快捷键（默认 shift，可避开 Questie 的 Shift）"])
    QCT:Print(L["  |cffffff00/qct logkey <alt|ctrl|none>|r - 任务日志里开详情窗的键（默认 alt）"])
    QCT:Print("  |cffffff00按住 Shift 再松开|r - 悬停在任务上，松开 Shift 才弹窗（按下时不弹，留给 Questie 隐藏任务）")
    QCT:Print("  |cffffff00Alt + 悬停任务起始物品|r - 背包/银行里的任务起始物品，按住 Alt 看它开启的整条链")
    QCT:Print("  |cffffff00/qct item|r - 物品诊断：鼠标下的物品有没有被认出来、能不能查到它开启的任务")
    QCT:Print("  |cffffff00/qct mute on|off|r - 静音：完全不画面板/详情窗，用来确认某个弹窗是不是本插件弹的")
    QCT:Print("  |cffffff00/qct map|r - 地图图标诊断：提示框持有者、图标矩形、光标位置、解析到的任务")
    QCT:Print(L["  |cffffff00/qct qlog|r - 任务日志快捷键诊断"])
    QCT:Print(L["  |cffffff00/qct mouse|r - 鼠标现在压在哪个帧上（祖先链 / ID / 提示框持有者）"])
    QCT:Print(L["  |cffffff00/qct width <auto|420-900>|r - 详情窗宽度"])
    QCT:Print(L["  |cffffff00/qct pwidth <240-560>|r - 悬停面板宽度"])
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
        -- 详情窗快捷键。Questie 也用 Shift，玩家可以改成 Ctrl / Alt、任意键，或直接关掉
        local want = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if want == "" then
            QCT:Print(L["用法: /qct key <shift|ctrl|alt|none|任意键>"])
        else
            QCT.db.chainKey = want:upper()
            if QCT.Tooltip and QCT.Tooltip.ApplyChainKey then
                pcall(QCT.Tooltip.ApplyChainKey, QCT.Tooltip)
            end
            local label = (QCT.Tooltip and QCT.Tooltip.ChainKeyLabel and QCT.Tooltip.ChainKeyLabel()) or want
            QCT:Print(L.F("详情窗快捷键: %s", label))
        end
    elseif cmd == "logkey" then
        -- 任务日志里开详情窗的键：Shift 要留给原生的「链接到聊天框」，默认 Alt
        local want = (rest or ""):gsub("%s+", ""):upper()
        if want == "ALT" or want == "CTRL" or want == "NONE" then
            QCT.db.questLogKey = want
            local label = (QCT.Tooltip and QCT.Tooltip.QuestLogKeyLabel and QCT.Tooltip.QuestLogKeyLabel()) or want
            QCT:Print(L.F("任务日志快捷键: %s", label))
        else
            QCT:Print(L["用法: /qct logkey <alt|ctrl|none>"])
        end
    elseif cmd == "width" then
        -- 详情窗宽度：auto 按屏幕算，也可以钉死一个像素值
        local want = (rest or ""):gsub("%s+", "")
        if want:lower() == "auto" then
            QCT.db.windowWidth = "AUTO"
        else
            local n = tonumber(want)
            if not n then
                QCT:Print(L["用法: /qct width <auto|420-900>"])
                return
            end
            if n < 420 then n = 420 end
            if n > 900 then n = 900 end
            QCT.db.windowWidth = math.floor(n)
        end
        if QCT.Window and QCT.Window.ApplyWidth then
            pcall(QCT.Window.ApplyWidth, QCT.Window)
        end
        local shown = QCT.Window and QCT.Window.ResolveWidth and QCT.Window:ResolveWidth() or 0
        QCT:Print(L.F("详情窗宽度: %d", shown))
    elseif cmd == "pwidth" then
        -- 悬停面板宽度（文本列宽，240~560）
        local n = tonumber((rest or ""):gsub("%s+", ""))
        if not n then
            QCT:Print(L["用法: /qct pwidth <240-560>"])
            return
        end
        if n < 240 then n = 240 end
        if n > 560 then n = 560 end
        QCT.db.panelWidth = math.floor(n)
        if QCT.Tooltip and QCT.Tooltip.Update and GameTooltip and GameTooltip:IsShown() then
            pcall(QCT.Tooltip.Refresh, QCT.Tooltip, true)
        end
        QCT:Print(L.F("悬停面板宽度: %d", QCT.db.panelWidth))
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
    elseif cmd == "health" then
        -- 1.5.26 起「血量数值显示」整个功能停用：它要不停扫框体、找血条、跟位置，
        -- 玩家反馈太费。代码没删，还在 Health.lua 里 —— 想要就把它加回 toc 的加载列表。
        QCT:Print("血量数值显示已停用（这个功能会一直扫框体找血条，太费）。")
        QCT:Print("想恢复：把 Health.lua 加回 QuestChainTip.toc 的加载列表，这一行代码也还在。")
    elseif cmd == "mute" or cmd == "silent" then
        local want = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if want == "on" then
            QCT.db.muted = true
        elseif want == "off" then
            QCT.db.muted = false
        else
            QCT.db.muted = not QCT.db.muted
        end
        if QCT.db.muted then
            if QCT.Tooltip and QCT.Tooltip.Hide then pcall(QCT.Tooltip.Hide, QCT.Tooltip) end
            if QCT.Window and QCT.Window.Close then pcall(QCT.Window.Close, QCT.Window) end
            QCT:Print("已|cffffff00静音|r：本插件的面板和详情窗都不会再画（按键也不再响应）。")
            QCT:Print("  现在按 Shift 悬停图标，如果还有弹窗，就不是本插件弹的。恢复：/qct mute off")
        else
            QCT:Print("已恢复：面板和详情窗正常显示。")
        end
    elseif cmd == "map" then
        if QCT.Tooltip and QCT.Tooltip.DiagnoseMapIcon then
            QCT.Tooltip:DiagnoseMapIcon()
        else
            QCT:Print("提示模块未加载")
        end
    elseif cmd == "item" then
        if QCT.Tooltip and QCT.Tooltip.DiagnoseItem then
            QCT.Tooltip:DiagnoseItem()
        else
            QCT:Print("提示模块未加载")
        end
    elseif cmd == "qlog" then
        if QCT.Tooltip and QCT.Tooltip.DiagnoseQuestLog then
            QCT.Tooltip:DiagnoseQuestLog()
        else
            QCT:Print("提示模块未加载")
        end
    elseif cmd == "mouse" then
        if QCT.Tooltip and QCT.Tooltip.DiagnoseMouse then
            QCT.Tooltip:DiagnoseMouse()
        else
            QCT:Print("提示模块未加载")
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
