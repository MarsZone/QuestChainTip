--[[
文本格式化：颜色、数字、金币、标题归一化、自动换行。
不依赖 Questie 也能工作（Questie 存在时会复用它的换行实现以获得一致效果）。
]]

local ADDON, ns = ...
local QCT = ns
local F = {}
QCT.Format = F

local floor = math.floor
local strformat = string.format

--------------------------------------------------------------------------------
-- 颜色
--------------------------------------------------------------------------------

local function clamp(v)
    if not v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

function F.Hex(r, g, b, text)
    return strformat("|cff%02x%02x%02x%s|r", floor(clamp(r) * 255 + 0.5), floor(clamp(g) * 255 + 0.5), floor(clamp(b) * 255 + 0.5), tostring(text))
end

F.DIM = "|cff9d9d9d"
F.WHITE = "|cffffffff"
F.GREEN = "|cff33ff33"
F.RED = "|cffff3030"
F.YELLOW = "|cffffd200"
F.BLUE = "|cff4a8cff"

function F.Grey(text)
    return F.DIM .. tostring(text) .. "|r"
end

--------------------------------------------------------------------------------
-- 任务难度颜色
--------------------------------------------------------------------------------

---@param level number
---@param questId number?
---@return number r, number g, number b
function F.DifficultyColor(level, questId)
    local mod = QCT.Data and QCT.Data.mod
    if mod and mod.QuestieLib then
        local ok, r, g, b = pcall(mod.QuestieLib.GetDifficultyColorPercent, mod.QuestieLib, level, questId)
        if ok and type(r) == "number" then
            return r, g, b
        end
    end

    local playerLevel = UnitLevel("player") or 1
    if not level or level <= 0 then level = playerLevel end
    local diff = level - playerLevel
    if diff >= 5 then
        return 1.00, 0.10, 0.10
    elseif diff >= 3 then
        return 1.00, 0.50, 0.25
    elseif diff >= -2 then
        return 1.00, 1.00, 0.00
    elseif diff >= -4 then
        return 0.25, 0.75, 0.25
    end
    return 0.50, 0.50, 0.50
end

function F.DifficultyText(level, questId, text)
    local r, g, b = F.DifficultyColor(level, questId)
    return F.Hex(r, g, b, text)
end

--------------------------------------------------------------------------------
-- 数字 / 金币
--------------------------------------------------------------------------------

function F.Number(n)
    n = tonumber(n) or 0
    local negative = n < 0
    if negative then n = -n end
    local s = tostring(floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    if negative then out = "-" .. out end
    return out
end

function F.Coins(copper)
    copper = floor(tonumber(copper) or 0)
    if copper <= 0 then return "" end

    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        local ok, s = pcall(C_CurrencyInfo.GetCoinTextureString, copper)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    if GetCoinTextureString then
        local ok, s = pcall(GetCoinTextureString, copper)
        if ok and type(s) == "string" and s ~= "" then return s end
    end

    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local copperOnly = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "金" end
    if silver > 0 then parts[#parts + 1] = silver .. "银" end
    if copperOnly > 0 or #parts == 0 then parts[#parts + 1] = copperOnly .. "铜" end
    return table.concat(parts, "")
end

--------------------------------------------------------------------------------
-- 文本清洗
--------------------------------------------------------------------------------

function F.StripCodes(text)
    if type(text) ~= "string" then return "" end
    local t = text
    t = t:gsub("|c%x%x%x%x%x%x%x%x", "")
    t = t:gsub("|r", "")
    t = t:gsub("|T.-|t", "")
    t = t:gsub("|A.-|a", "")
    t = t:gsub("|H[^|]*|h(.-)|h", "%1")
    return t
end

---把任务标题归一化，便于和任务日志标题做匹配。
---会去掉颜色代码、等级前缀 "[38] "、以及尾部的 "(可接)" 之类的状态标记。
---@param text string?
---@return string?
---把任务标题归一化，用于"标题 -> 任务ID"的匹配。
---注意：客户端可能返回 secret string（加密字符串），对这类值做任何字符串处理都会抛错，
---所以整段用 pcall 包住，处理不了就返回 nil，由调用方走别的识别路径。
function F.NormalizeTitle(text)
    if type(text) ~= "string" then return nil end

    local ok, result = pcall(function()
        local t = F.StripCodes(text)
        t = t:gsub("^%s+", ""):gsub("%s+$", "")
        t = t:gsub("^%[%s*%d+%s*%+?%s*%]%s*", "")
        for _ = 1, 2 do
            t = t:gsub("%s*[%(（][^%)）]*[%)）]%s*$", "")
        end
        t = t:gsub("%s+", " ")
        if t == "" then return nil end
        return t
    end)

    if not ok then return nil end
    return result
end

--------------------------------------------------------------------------------
-- 自动换行
--------------------------------------------------------------------------------

local wrapCache = {}
local wrapCacheSize = 0

local function nextCharIndex(s, i)
    local byte = s:byte(i)
    if not byte then return i + 1 end
    if byte >= 0xF0 then return i + 4 end
    if byte >= 0xE0 then return i + 3 end
    if byte >= 0xC0 then return i + 2 end
    return i + 1
end

local measureFS
local function getMeasureFontString(fontSource)
    if not measureFS then
        measureFS = UIParent:CreateFontString(nil, "ARTWORK", "GameTooltipText")
        measureFS:Hide()
    end
    if fontSource and fontSource.GetFont then
        local font, size, flags = fontSource:GetFont()
        if font and size then
            local curFont, curSize, curFlags = measureFS:GetFont()
            if curFont ~= font or curSize ~= size or curFlags ~= flags then
                measureFS:SetFont(font, size, flags)
            end
        end
    end
    return measureFS
end

local function measureText(text, fontSource)
    local fs = getMeasureFontString(fontSource)
    fs:SetText(text or "")
    local width = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or 0
    if not width or width <= 0 then
        width = fs:GetStringWidth() or 0
    end
    return width
end

---贪心换行（按渲染宽度测量，中文按字断行）。
---@param text string
---@param prefix string 每行前缀（用于缩进）
---@param width number 可用宽度（像素）
---@param fontSource FontString?
---@return string[]
local function wrapByMeasure(text, prefix, width, fontSource)
    local lines = {}
    local total = #text
    local start = 1
    while start <= total do
        local i = start
        local current = ""
        while i <= total do
            local ni = nextCharIndex(text, i)
            local chunk = text:sub(i, ni - 1)
            local candidate = current .. chunk
            if current ~= "" and measureText(prefix .. candidate, fontSource) > width then
                break
            end
            current = candidate
            i = ni
        end
        if current == "" then
            local ni = nextCharIndex(text, start)
            current = text:sub(start, ni - 1)
            i = ni
        end
        lines[#lines + 1] = prefix .. current
        start = i
        while start <= total and text:sub(start, start) == " " do
            start = start + 1
        end
    end
    return lines
end

---把一段文字按宽度折行，返回带前缀的行数组。
---@param text string?
---@param prefix string? 每行前缀（缩进）
---@param width number 可用宽度（像素）
---@param fontSource FontString?
---@return string[]
function F.Wrap(text, prefix, width, fontSource)
    if type(text) ~= "string" or text == "" then return {} end
    prefix = prefix or ""
    width = width or 300

    local normalized = text:gsub("\r", ""):gsub("\n", " "):gsub("%s+", " ")
    local key = width .. "\1" .. prefix .. "\1" .. normalized
    local cached = wrapCache[key]
    if cached then return cached end

    local lines = wrapByMeasure(normalized, prefix, width, fontSource)

    if wrapCacheSize > 500 then
        wrapCache = {}
        wrapCacheSize = 0
    end
    wrapCache[key] = lines
    wrapCacheSize = wrapCacheSize + 1
    return lines
end

function F.ClearWrapCache()
    wrapCache = {}
    wrapCacheSize = 0
end
