--[[
本地化：zhCN / zhTW / enUS

设计要点：
  * **以简体原文作为 key**。zhCN 不维护表——查不到就返回 key 自身，所以
    现有代码的文案一个字都不用改，风险为零；只需要补 zhTW 和 enUS 两张表。
  * 繁体客户端和英文客户端的字体都不含简体字形（英文的 FRIZQT 更是完全没有
    CJK 字形），所以这些字在那边会渲染成方块，必须走本地化，不能靠换字体。
  * L["文案"] 走 metatable 兜底；带占位符的用 L.F("文案 %d", n)。
  * /qct locale <zhCN|zhTW|enUS|auto> 可以手动覆盖，照顾「客户端语言和习惯语言不一致」的玩家。
]]

local ADDON, ns = ...
local QCT = ns

local L = {}
QCT.Locale = L

local FALLBACK = "enUS"

local function Normalize(loc)
    if loc == "zhCN" or loc == "zhTW" or loc == "enUS" then return loc end
    if type(loc) == "string" and loc:sub(1, 2) == "en" then return "enUS" end
    return FALLBACK
end

local function ClientLocale()
    local ok, loc = pcall(function() return GetLocale() end)
    if ok and type(loc) == "string" and loc ~= "" then return Normalize(loc) end
    return FALLBACK
end

local current = ClientLocale()

--------------------------------------------------------------------------------
-- 繁体
--------------------------------------------------------------------------------

local zhTW = {
    -- 通用
    ["|cff33ff99任务链提示|r: "] = "|cff33ff99任務鏈提示|r: ",
    ["任务链提示"] = "任務鏈提示",
    ["显示血量数值（目标/焦点血条上）"] = "顯示血量數值（目標/焦點血條上）",
    ["显示小地图图标"] = "顯示小地圖圖示",
    ["左键打开设置"] = "左鍵開啟設定",
    ["拖动可调整位置"] = "拖曳可調整位置",
    ["开"] = "開",
    ["关"] = "關",
    ["是"] = "是",
    ["否"] = "否",

    -- 任务状态（面板里带括号）
    ["(进行中)"] = "(進行中)",
    ["(已完成)"] = "(已完成)",
    ["(可接)"] = "(可接)",
    ["(条件不足)"] = "(條件不足)",
    ["(未知)"] = "(未知)",

    -- 任务状态（详情窗里不带括号）
    ["进行中"] = "進行中",
    ["已完成"] = "已完成",
    ["可接"] = "可接",
    ["条件不足"] = "條件不足",
    ["未知"] = "未知",

    -- 链条角色
    ["前置"] = "前置",
    ["当前"] = "當前",
    ["后续"] = "後續",

    -- 面板区块
    ["任务描述"] = "任務描述",
    ["任务奖励"] = "任務獎勵",
    ["后续任务"] = "後續任務",
    ["前置任务"] = "前置任務",
    ["任务详情"] = "任務詳情",
    ["完成条件"] = "完成條件",
    ["奖励"] = "獎勵",
    ["接取："] = "接取：",
    ["交付："] = "交付：",
    ["副本任务"] = "副本任務",
    ["团队副本"] = "團隊副本",
    ["经验"] = "經驗",
    ["金"] = "金",
    ["银"] = "銀",
    ["铜"] = "銅",
    ["任务 %s"] = "任務 %s",

    -- 截断与提示
    ["…（在世界地图上按住 %s 查看完整任务链）"] = "…（在世界地圖上按住 %s 查看完整任務鏈）",
    ["…（描述较长，已截断）"] = "…（描述較長，已截斷）",
    ["…（条件较多，已截断）"] = "…（條件較多，已截斷）",
    ["已隐藏 %d 个已完成的任务 · 点右上角「显示全部」展开"] = "已隱藏 %d 個已完成的任務 · 點右上角「顯示全部」展開",
    ["没有取到任务数据（Questie 数据源可能未就绪）"] = "沒有取得任務資料（Questie 資料來源可能尚未就緒）",
    ["（%d 环，已隐藏 %d 个已完成）"] = "（%d 環，已隱藏 %d 個已完成）",
    ["（%d 环）"] = "（%d 環）",
    ["任务链详情 · %s"] = "任務鏈詳情 · %s",
    ["隐藏已完成"] = "隱藏已完成",
    ["显示全部 (%d)"] = "顯示全部 (%d)",
    ["任务链窗口渲染出错：%s"] = "任務鏈視窗顯示錯誤：%s",

    -- 设置界面
    ["任务链提示 - 设置"] = "任務鏈提示 - 設定",
    ["在世界地图上悬停任务图标显示简介，按住 %s 打开整条任务链详情窗；小地图上不弹"] =
        "在世界地圖上將滑鼠移到任務圖示顯示簡介，按住 %s 開啟整條任務鏈詳情視窗；小地圖上不顯示",
    ["启用插件"] = "啟用插件",
    ["悬停面板"] = "懸停面板",
    ["悬停面板宽度"] = "懸停面板寬度",
    ["详情窗宽度"] = "詳情視窗寬度",
    ["插件版本: %s"] = "插件版本: %s",
    ["任务日志快捷键"] = "任務日誌快捷鍵",
    ["  |cffffff00/qct logkey <alt|ctrl|none>|r - 任务日志里开详情窗的键（默认 alt）"] =
        "  |cffffff00/qct logkey <alt|ctrl|none>|r - 任務日誌裡開詳情視窗的鍵（預設 alt）",
    ["用法: /qct logkey <alt|ctrl|none>"] = "用法: /qct logkey <alt|ctrl|none>",
    ["任务日志快捷键: %s"] = "任務日誌快捷鍵: %s",
    ["  |cffffff00/qct health|r - 血量显示诊断（框体/血条/文字状态）"] =
        "  |cffffff00/qct health|r - 血量顯示診斷（框體/血條/文字狀態）",
    ["  |cffffff00/qct qlog|r - 任务日志快捷键诊断"] =
        "  |cffffff00/qct qlog|r - 任務日誌快捷鍵診斷",
    ["  |cffffff00/qct mouse|r - 鼠标现在压在哪个帧上（祖先链 / ID / 提示框持有者）"] =
        "  |cffffff00/qct mouse|r - 滑鼠現在壓在哪個幀上（祖先鏈 / ID / 提示框持有者）",
    ["自动"] = "自動",
    ["窄"] = "窄",
    ["标准"] = "標準",
    ["宽"] = "寬",
    ["详情窗快捷键"] = "詳情視窗快捷鍵",
    ["不启用"] = "不啟用",
    ["自定义…"] = "自訂…",
    ["请按下一个按键"] = "請按下一個按鍵",
    ["Esc 或点击空白处取消 · 自定义键会占用该键原本的绑定"] =
        "Esc 或點擊空白處取消 · 自訂鍵會佔用該鍵原本的綁定",
    ["不显示"] = "不顯示",
    ["仅世界地图"] = "僅世界地圖",
    ["全部位置"] = "全部位置",
    ["显示任务描述"] = "顯示任務描述",
    ["描述最多行数"] = "描述最多行數",
    ["显示任务奖励（经验/金钱/物品/声望）"] = "顯示任務獎勵（經驗/金錢/物品/聲望）",
    ["显示后续任务链"] = "顯示後續任務鏈",
    ["后续任务每行显示奖励与状态"] = "後續任務每列顯示獎勵與狀態",
    ["普通状态显示层数"] = "一般狀態顯示層數",
    ["详情窗最多显示环数"] = "詳情視窗最多顯示環數",
    ["显示前置任务"] = "顯示前置任務",
    ["聊天框显示诊断信息（排查问题时用）"] = "聊天視窗顯示診斷資訊（排查問題時用）",
    ["调试输出（排查问题时用）"] = "除錯輸出（排查問題時用）",
    ["恢复默认"] = "恢復預設",
    ["已恢复默认设置"] = "已恢復預設設定",
    ["关闭"] = "關閉",
    ["提示：设置会保存在 QuestChainTipDB"] = "提示：設定會儲存在 QuestChainTipDB",

    -- 聊天框提示
    ["没有找到 Questie / QuestieDB，本插件需要它们提供任务数据，请确认 Questie 已启用。"] =
        "找不到 Questie / QuestieDB，本插件需要它們提供任務資料，請確認 Questie 已啟用。",
    ["输入 |cffffff00/qct why|r 可以查看详细状态。"] = "輸入 |cffffff00/qct why|r 可以查看詳細狀態。",
    ["没有读到 Questie 的任务数据（请确认 Questie 已启用）。输入 |cffffff00/qct why|r 查看详情。"] =
        "沒有讀到 Questie 的任務資料（請確認 Questie 已啟用）。輸入 |cffffff00/qct why|r 查看詳情。",
    ["面板渲染出错：%s"] = "面板顯示錯誤：%s",
    ["没有可显示的任务：先把鼠标移到任务上，或先打开任务日志。"] =
        "沒有可顯示的任務：先將滑鼠移到任務上，或先開啟任務日誌。",
    ["设置界面未加载"] = "設定介面未載入",
    ["插件已%s"] = "插件已%s",
    ["|cff00ff00开启|r"] = "|cff00ff00開啟|r",
    ["|cffff0000关闭|r"] = "|cffff0000關閉|r",
    ["任务描述: %s"] = "任務描述: %s",
    ["任务奖励: %s"] = "任務獎勵: %s",
    ["后续任务链: %s"] = "後續任務鏈: %s",
    ["后续任务奖励行: %s"] = "後續任務獎勵列: %s",
    ["前置任务: %s"] = "前置任務: %s",
    ["详情窗最多环数: %d"] = "詳情視窗最多環數: %d",
    ["请输入 1-20 的数字"] = "請輸入 1-20 的數字",
    ["普通状态后续任务层数: %d"] = "一般狀態後續任務層數: %d",
    ["调试输出: %s"] = "除錯輸出: %s",
    ["聊天框诊断信息: %s"] = "聊天視窗診斷資訊: %s",
    ["任务日志条目: %d"] = "任務日誌項目: %d",
    ["日志已清空"] = "日誌已清空",
    ["已探测任务 %d 的奖励接口，结果写入日志。输入 |cffffff00/qct trace 12|r 查看。"] =
        "已探測任務 %d 的獎勵介面，結果寫入日誌。輸入 |cffffff00/qct trace 12|r 查看。",
    ["用法: /qct rewards <任务ID>"] = "用法: /qct rewards <任務ID>",
    ["用法: /qct detail <任务ID>（或者把鼠标悬停在任务上再输入）"] =
        "用法: /qct detail <任務ID>（或將滑鼠移到任務上再輸入）",
    ["用法: /qct dump <任务ID>"] = "用法: /qct dump <任務ID>",

    -- 命令帮助
    ["命令:"] = "指令:",
    ["  |cffffff00/qct|r - 打开设置界面"] = "  |cffffff00/qct|r - 開啟設定介面",
    ["  |cffffff00/qct on|off|r - 启用/关闭"] = "  |cffffff00/qct on|off|r - 啟用/關閉",
    ["  |cffffff00/qct desc|reward|chain|reward2|prereq|r - 分项开关"] =
        "  |cffffff00/qct desc|reward|chain|reward2|prereq|r - 分項開關",
    ["  |cffffff00/qct depth <n>|r - 普通状态下后续任务层数 (当前 %d)"] =
        "  |cffffff00/qct depth <n>|r - 一般狀態下後續任務層數 (目前 %d)",
    ["  |cffffff00/qct depthshift <n>|r - 详情窗最多环数 (当前 %d)"] =
        "  |cffffff00/qct depthshift <n>|r - 詳情視窗最多環數 (目前 %d)",
    ["  |cffffff00/qct debug|r - 调试输出"] = "  |cffffff00/qct debug|r - 除錯輸出",
    ["  |cffffff00/qct explain|r - 聊天框诊断信息（为什么没开窗，默认关）"] =
        "  |cffffff00/qct explain|r - 聊天視窗診斷資訊（為什麼沒開窗，預設關閉）",
    ["  |cffffff00/qct log|r - 列出当前任务日志的识别结果"] =
        "  |cffffff00/qct log|r - 列出目前任務日誌的辨識結果",
    ["  |cffffff00/qct dump <任务ID>|r - 打印某任务解析结果"] =
        "  |cffffff00/qct dump <任務ID>|r - 列印某任務解析結果",
    ["  |cffffff00/qct test|r - 强制画一个测试面板（检查显示是否正常）"] =
        "  |cffffff00/qct test|r - 強制畫一個測試面板（檢查顯示是否正常）",
    ["  |cffffff00/qct detail <任务ID>|r - 打开任务链详情窗（等价于在地图上按快捷键）"] =
        "  |cffffff00/qct detail <任務ID>|r - 開啟任務鏈詳情視窗（等同於在地圖上按快捷鍵）",
    ["  |cffffff00/qct rewards <任务ID>|r - 探测该任务的奖励接口，结果写入日志"] =
        "  |cffffff00/qct rewards <任務ID>|r - 探測該任務的獎勵介面，結果寫入日誌",
    ["  |cffffff00/qct why|r - 打印运行状态，排查为什么没显示"] =
        "  |cffffff00/qct why|r - 列印執行狀態，排查為什麼沒顯示",
    ["  |cffffff00/qct trace|r - 打印后台日志（默认一直在记，无需开启）"] =
        "  |cffffff00/qct trace|r - 列印背景日誌（預設一直在記錄，無需開啟）",
    ["  |cffffff00/qct key <shift|ctrl|alt|none|任意键>|r - 详情窗快捷键（默认 shift，可避开 Questie 的 Shift）"] =
        "  |cffffff00/qct key <shift|ctrl|alt|none|任意鍵>|r - 詳情視窗快捷鍵（預設 shift，可避開 Questie 的 Shift）",
    ["用法: /qct key <shift|ctrl|alt|none|任意键>"] = "用法: /qct key <shift|ctrl|alt|none|任意鍵>",
    ["  |cffffff00/qct width <auto|420-900>|r - 详情窗宽度"] =
        "  |cffffff00/qct width <auto|420-900>|r - 詳情視窗寬度",
    ["  |cffffff00/qct pwidth <240-560>|r - 悬停面板宽度"] =
        "  |cffffff00/qct pwidth <240-560>|r - 懸停面板寬度",
    ["用法: /qct width <auto|420-900>"] = "用法: /qct width <auto|420-900>",
    ["用法: /qct pwidth <240-560>"] = "用法: /qct pwidth <240-560>",
    ["详情窗宽度: %d"] = "詳情視窗寬度: %d",
    ["悬停面板宽度: %d"] = "懸停面板寬度: %d",
    ["详情窗快捷键: %s"] = "詳情視窗快捷鍵: %s",
    ["  |cffffff00/qct locale <zhCN|zhTW|enUS|auto>|r - 切换界面语言"] =
        "  |cffffff00/qct locale <zhCN|zhTW|enUS|auto>|r - 切換介面語言",
    ["界面语言: %s"] = "介面語言: %s",
    ["界面语言已切换为 %s（/reload 后完全生效）"] = "介面語言已切換為 %s（/reload 後完全生效）",
}

--------------------------------------------------------------------------------
-- 英文
--------------------------------------------------------------------------------

local enUS = {
    -- 通用
    ["|cff33ff99任务链提示|r: "] = "|cff33ff99Quest Chain Tip|r: ",
    ["任务链提示"] = "Quest Chain Tip",
    ["显示血量数值（目标/焦点血条上）"] = "Show health values (target/focus bar)",
    ["显示小地图图标"] = "Show minimap button",
    ["左键打开设置"] = "Left-click to open settings",
    ["拖动可调整位置"] = "Drag to move",
    ["开"] = "on",
    ["关"] = "off",
    ["是"] = "yes",
    ["否"] = "no",

    -- 任务状态（面板里带括号）
    ["(进行中)"] = "(In progress)",
    ["(已完成)"] = "(Completed)",
    ["(可接)"] = "(Available)",
    ["(条件不足)"] = "(Locked)",
    ["(未知)"] = "(Unknown)",

    -- 任务状态（详情窗里不带括号）
    ["进行中"] = "In progress",
    ["已完成"] = "Completed",
    ["可接"] = "Available",
    ["条件不足"] = "Locked",
    ["未知"] = "Unknown",

    -- 链条角色
    ["前置"] = "Prereq",
    ["当前"] = "Current",
    ["后续"] = "Next",

    -- 面板区块
    ["任务描述"] = "Description",
    ["任务奖励"] = "Rewards",
    ["后续任务"] = "Follow-up quests",
    ["前置任务"] = "Prerequisites",
    ["任务详情"] = "Quest text",
    ["完成条件"] = "Objectives",
    ["奖励"] = "Rewards",
    ["接取："] = "Start: ",
    ["交付："] = "Turn in: ",
    ["副本任务"] = "Dungeon",
    ["团队副本"] = "Raid",
    ["经验"] = "XP",
    ["金"] = "g",
    ["银"] = "s",
    ["铜"] = "c",
    ["任务 %s"] = "Quest %s",

    -- 截断与提示
    ["…（在世界地图上按住 %s 查看完整任务链）"] = "… (hold %s on the world map for the full chain)",
    ["…（描述较长，已截断）"] = "… (description truncated)",
    ["…（条件较多，已截断）"] = "… (objectives truncated)",
    ["已隐藏 %d 个已完成的任务 · 点右上角「显示全部」展开"] =
        "%d completed quest(s) hidden · click \"Show all\" in the top-right to expand",
    ["没有取到任务数据（Questie 数据源可能未就绪）"] =
        "No quest data (the Questie database may not be ready yet)",
    ["（%d 环，已隐藏 %d 个已完成）"] = "(%d steps, %d completed hidden)",
    ["（%d 环）"] = "(%d steps)",
    ["任务链详情 · %s"] = "Quest chain · %s",
    ["隐藏已完成"] = "Hide completed",
    ["显示全部 (%d)"] = "Show all (%d)",
    ["任务链窗口渲染出错：%s"] = "Chain window render error: %s",

    -- 设置界面
    ["任务链提示 - 设置"] = "Quest Chain Tip - Settings",
    ["在世界地图上悬停任务图标显示简介，按住 %s 打开整条任务链详情窗；小地图上不弹"] =
        "Hover a world map quest marker for the summary panel, hold %s for the full chain window. Never shown on the minimap.",
    ["启用插件"] = "Enable addon",
    ["悬停面板"] = "Hover panel",
    ["悬停面板宽度"] = "Panel width",
    ["详情窗宽度"] = "Window width",
    ["插件版本: %s"] = "Addon version: %s",
    ["任务日志快捷键"] = "Quest log key",
    ["  |cffffff00/qct logkey <alt|ctrl|none>|r - 任务日志里开详情窗的键（默认 alt）"] =
        "  |cffffff00/qct logkey <alt|ctrl|none>|r - key that opens the chain window from the quest log (default alt)",
    ["用法: /qct logkey <alt|ctrl|none>"] = "Usage: /qct logkey <alt|ctrl|none>",
    ["任务日志快捷键: %s"] = "Quest log key: %s",
    ["  |cffffff00/qct health|r - 血量显示诊断（框体/血条/文字状态）"] =
        "  |cffffff00/qct health|r - health display diagnostics (frame / bar / text)",
    ["  |cffffff00/qct qlog|r - 任务日志快捷键诊断"] =
        "  |cffffff00/qct qlog|r - quest log hotkey diagnostics",
    ["  |cffffff00/qct mouse|r - 鼠标现在压在哪个帧上（祖先链 / ID / 提示框持有者）"] =
        "  |cffffff00/qct mouse|r - which frame is under the mouse (ancestors / ID / tooltip owner)",
    ["自动"] = "Auto",
    ["窄"] = "Narrow",
    ["标准"] = "Standard",
    ["宽"] = "Wide",
    ["详情窗快捷键"] = "Chain window key",
    ["不启用"] = "Disabled",
    ["自定义…"] = "Custom...",
    ["请按下一个按键"] = "Press a key",
    ["Esc 或点击空白处取消 · 自定义键会占用该键原本的绑定"] =
        "Esc or click elsewhere to cancel · a custom key takes over that key's original binding",
    ["不显示"] = "Off",
    ["仅世界地图"] = "World map only",
    ["全部位置"] = "Everywhere",
    ["显示任务描述"] = "Show quest description",
    ["描述最多行数"] = "Max description lines",
    ["显示任务奖励（经验/金钱/物品/声望）"] = "Show rewards (XP / money / items / reputation)",
    ["显示后续任务链"] = "Show follow-up chain",
    ["后续任务每行显示奖励与状态"] = "Show rewards and state on each follow-up line",
    ["普通状态显示层数"] = "Chain depth (hover panel)",
    ["详情窗最多显示环数"] = "Max chain length (window)",
    ["显示前置任务"] = "Show prerequisites",
    ["聊天框显示诊断信息（排查问题时用）"] = "Chat diagnostics (troubleshooting)",
    ["调试输出（排查问题时用）"] = "Debug output (troubleshooting)",
    ["恢复默认"] = "Reset to defaults",
    ["已恢复默认设置"] = "Settings restored to defaults",
    ["关闭"] = "Close",
    ["提示：设置会保存在 QuestChainTipDB"] = "Settings are stored in QuestChainTipDB",

    -- 聊天框提示
    ["没有找到 Questie / QuestieDB，本插件需要它们提供任务数据，请确认 Questie 已启用。"] =
        "Questie / QuestieDB not found. This addon needs them for quest data — make sure Questie is enabled.",
    ["输入 |cffffff00/qct why|r 可以查看详细状态。"] = "Type |cffffff00/qct why|r for details.",
    ["没有读到 Questie 的任务数据（请确认 Questie 已启用）。输入 |cffffff00/qct why|r 查看详情。"] =
        "Could not read Questie quest data (make sure Questie is enabled). Type |cffffff00/qct why|r for details.",
    ["面板渲染出错：%s"] = "Panel render error: %s",
    ["没有可显示的任务：先把鼠标移到任务上，或先打开任务日志。"] =
        "Nothing to show: hover a quest first, or open the quest log.",
    ["设置界面未加载"] = "Settings panel not loaded",
    ["插件已%s"] = "Addon %s",
    ["|cff00ff00开启|r"] = "|cff00ff00enabled|r",
    ["|cffff0000关闭|r"] = "|cffff0000disabled|r",
    ["任务描述: %s"] = "Quest description: %s",
    ["任务奖励: %s"] = "Quest rewards: %s",
    ["后续任务链: %s"] = "Follow-up chain: %s",
    ["后续任务奖励行: %s"] = "Follow-up reward lines: %s",
    ["前置任务: %s"] = "Prerequisites: %s",
    ["详情窗最多环数: %d"] = "Max chain length (window): %d",
    ["请输入 1-20 的数字"] = "Enter a number between 1 and 20",
    ["普通状态后续任务层数: %d"] = "Chain depth (hover panel): %d",
    ["调试输出: %s"] = "Debug output: %s",
    ["聊天框诊断信息: %s"] = "Chat diagnostics: %s",
    ["任务日志条目: %d"] = "Quest log entries: %d",
    ["日志已清空"] = "Log cleared",
    ["已探测任务 %d 的奖励接口，结果写入日志。输入 |cffffff00/qct trace 12|r 查看。"] =
        "Probed reward APIs for quest %d, results written to the log. Type |cffffff00/qct trace 12|r to view.",
    ["用法: /qct rewards <任务ID>"] = "Usage: /qct rewards <questID>",
    ["用法: /qct detail <任务ID>（或者把鼠标悬停在任务上再输入）"] =
        "Usage: /qct detail <questID> (or hover a quest first)",
    ["用法: /qct dump <任务ID>"] = "Usage: /qct dump <questID>",

    -- 命令帮助
    ["命令:"] = "Commands:",
    ["  |cffffff00/qct|r - 打开设置界面"] = "  |cffffff00/qct|r - open settings",
    ["  |cffffff00/qct on|off|r - 启用/关闭"] = "  |cffffff00/qct on|off|r - enable / disable",
    ["  |cffffff00/qct desc|reward|chain|reward2|prereq|r - 分项开关"] =
        "  |cffffff00/qct desc|reward|chain|reward2|prereq|r - toggle individual sections",
    ["  |cffffff00/qct depth <n>|r - 普通状态下后续任务层数 (当前 %d)"] =
        "  |cffffff00/qct depth <n>|r - chain depth for the hover panel (now %d)",
    ["  |cffffff00/qct depthshift <n>|r - 详情窗最多环数 (当前 %d)"] =
        "  |cffffff00/qct depthshift <n>|r - max chain length in the window (now %d)",
    ["  |cffffff00/qct debug|r - 调试输出"] = "  |cffffff00/qct debug|r - debug output",
    ["  |cffffff00/qct explain|r - 聊天框诊断信息（为什么没开窗，默认关）"] =
        "  |cffffff00/qct explain|r - chat diagnostics (why no window opened; off by default)",
    ["  |cffffff00/qct log|r - 列出当前任务日志的识别结果"] =
        "  |cffffff00/qct log|r - list what was recognised in the current quest log",
    ["  |cffffff00/qct dump <任务ID>|r - 打印某任务解析结果"] =
        "  |cffffff00/qct dump <questID>|r - print the parsed data for a quest",
    ["  |cffffff00/qct test|r - 强制画一个测试面板（检查显示是否正常）"] =
        "  |cffffff00/qct test|r - force-draw a test panel (checks rendering)",
    ["  |cffffff00/qct detail <任务ID>|r - 打开任务链详情窗（等价于在地图上按快捷键）"] =
        "  |cffffff00/qct detail <questID>|r - open the chain window (same as the key on the world map)",
    ["  |cffffff00/qct rewards <任务ID>|r - 探测该任务的奖励接口，结果写入日志"] =
        "  |cffffff00/qct rewards <questID>|r - probe reward APIs, results go to the log",
    ["  |cffffff00/qct why|r - 打印运行状态，排查为什么没显示"] =
        "  |cffffff00/qct why|r - print runtime state, to diagnose why nothing shows",
    ["  |cffffff00/qct trace|r - 打印后台日志（默认一直在记，无需开启）"] =
        "  |cffffff00/qct trace|r - print the background log (always recording)",
    ["  |cffffff00/qct key <shift|ctrl|alt|none|任意键>|r - 详情窗快捷键（默认 shift，可避开 Questie 的 Shift）"] =
        "  |cffffff00/qct key <shift|ctrl|alt|none|任意键>|r - chain window key (default shift; avoids Questie's Shift)",
    ["用法: /qct key <shift|ctrl|alt|none|任意键>"] = "Usage: /qct key <shift|ctrl|alt|none|any key>",
    ["  |cffffff00/qct width <auto|420-900>|r - 详情窗宽度"] =
        "  |cffffff00/qct width <auto|420-900>|r - chain window width",
    ["  |cffffff00/qct pwidth <240-560>|r - 悬停面板宽度"] =
        "  |cffffff00/qct pwidth <240-560>|r - hover panel width",
    ["用法: /qct width <auto|420-900>"] = "Usage: /qct width <auto|420-900>",
    ["用法: /qct pwidth <240-560>"] = "Usage: /qct pwidth <240-560>",
    ["详情窗宽度: %d"] = "Chain window width: %d",
    ["悬停面板宽度: %d"] = "Panel width: %d",
    ["详情窗快捷键: %s"] = "Chain window key: %s",
    ["  |cffffff00/qct locale <zhCN|zhTW|enUS|auto>|r - 切换界面语言"] =
        "  |cffffff00/qct locale <zhCN|zhTW|enUS|auto>|r - switch UI language",
    ["界面语言: %s"] = "UI language: %s",
    ["界面语言已切换为 %s（/reload 后完全生效）"] = "UI language set to %s (/reload to apply everywhere)",
}

--------------------------------------------------------------------------------
-- 取值
--------------------------------------------------------------------------------

local PACKS = {
    zhTW = zhTW,
    enUS = enUS,
    -- zhCN 没有表：key 就是简体原文，查不到直接返回 key 自身
}

local function Lookup(key)
    if type(key) ~= "string" then return key end
    local pack = PACKS[current]
    if pack then
        local value = pack[key]
        if value ~= nil then return value end
    end
    return key
end

setmetatable(L, {
    __index = function(_, key) return Lookup(key) end,
})

function L.Get(key)
    return Lookup(key)
end

---带占位符的取法：L.F("任务 %s", id)。格式化失败时退回原文，不抛错。
function L.F(key, ...)
    local fmt = Lookup(key)
    if select("#", ...) == 0 then return fmt end
    local ok, out = pcall(string.format, fmt, ...)
    if ok and type(out) == "string" then return out end
    return fmt
end

function L.SetLocale(loc)
    if loc == nil or loc == "" or loc == "auto" then
        current = ClientLocale()
    else
        current = Normalize(loc)
    end
    return current
end

function L.Current()
    return current
end

---当前语言是不是中日韩文字（决定换行是按字断还是按词断）
function L.IsCJK()
    return current == "zhCN" or current == "zhTW"
end

---给测试用：直接拿某语言的包
function L.Pack(loc)
    return PACKS[Normalize(loc)]
end

L.LANGUAGES = { "zhCN", "zhTW", "enUS" }
