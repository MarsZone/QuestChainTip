--[[
任务链详情窗：在世界地图上按住 Shift 时弹出，把整条任务链上每个任务的
完成条件 / 奖励 / 任务详情 / 在哪接 / 在哪交 / 是否副本任务 全部列出来。

仍然遵守本插件的两条铁律：
1. 不碰 GameTooltip（避免闪烁），也绝不读 tooltip 文本（secret value 会抛错）。
2. 自绘 Frame，不用 GameTooltipTemplate 之类的模板帧。
]]

local ADDON, ns = ...
local QCT = ns
local L = QCT.Locale
local F = QCT.Format
local D = QCT.Data

local W = {}
QCT.Window = W

local WINDOW_NAME = "QuestChainTipWindow"
local DEFAULT_WIDTH, HEIGHT = 580, 640
local MIN_WIDTH, MAX_WIDTH = 420, 900
local PAD = 16
local TITLE_HEIGHT = 30
local SCROLLBAR_WIDTH = 8

-- 当前实际宽度。原来写死 580，任务描述和奖励物品名经常被迫折行；
-- 现在由配置决定（设置里「详情窗宽度」，默认按屏幕宽度自适应）。
local width = DEFAULT_WIDTH
local contentWidth = DEFAULT_WIDTH - PAD * 2 - SCROLLBAR_WIDTH - 8

local LINE_GAP = 2
local BLOCK_GAP = 10
local MAX_DESC_LINES = 8
local MAX_OBJECTIVE_LINES = 8

local INDENT = "    "

local STATE_TEXT = {
    active = { text = L["进行中"], r = 1.00, g = 0.82, b = 0.00 },
    completed = { text = L["已完成"], r = 0.55, g = 0.55, b = 0.55 },
    available = { text = L["可接"], r = 0.25, g = 1.00, b = 0.25 },
    locked = { text = L["条件不足"], r = 0.90, g = 0.40, b = 0.40 },
    unknown = { text = L["未知"], r = 0.60, g = 0.60, b = 0.60 },
}

local KIND_TEXT = {
    prereq = { text = L["前置"], r = 0.60, g = 0.60, b = 0.60 },
    current = { text = L["当前"], r = 1.00, g = 0.82, b = 0.00 },
    next = { text = L["后续"], r = 0.35, g = 0.85, b = 1.00 },
}

--------------------------------------------------------------------------------
-- 小工具
--------------------------------------------------------------------------------

local fontPath, fontSize, fontFlags

local function GetFont()
    if fontPath then return fontPath, fontSize, fontFlags end

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

local function StateLine(state)
    local info = STATE_TEXT[state] or STATE_TEXT.unknown
    return F.Hex(info.r, info.g, info.b, info.text)
end

local function KindTag(kind)
    local info = KIND_TEXT[kind] or KIND_TEXT.next
    return F.Hex(info.r, info.g, info.b, "[" .. info.text .. "]")
end

--------------------------------------------------------------------------------
-- 宽度
--------------------------------------------------------------------------------

---把配置里的宽度解析成实际像素。
---"AUTO"（默认）按屏幕宽度的 44% 算：1080p 下约 760，窗口够宽又不至于顶满屏幕。
---@return number
function W:ResolveWidth()
    local value = QCT.db and QCT.db.windowWidth
    local screen = 1280
    if UIParent and type(UIParent.GetWidth) == "function" then
        local ok, w = pcall(UIParent.GetWidth, UIParent)
        if ok and tonumber(w) and w > 200 then screen = w end
    end

    local result
    if value == "AUTO" or value == nil or value == 0 then
        result = math.floor(screen * 0.44)
    else
        result = tonumber(value) or DEFAULT_WIDTH
    end
    if result < MIN_WIDTH then result = MIN_WIDTH end
    if result > MAX_WIDTH then result = MAX_WIDTH end

    width = result
    contentWidth = width - PAD * 2 - SCROLLBAR_WIDTH - 8
    return width
end

---把宽度应用到已建好的控件上；窗口正开着就按新宽度重排一次
function W:ApplyWidth()
    local newWidth = self:ResolveWidth()
    if not self.frame then return newWidth end
    self.frame:SetSize(newWidth, HEIGHT)
    if self.content then self.content:SetWidth(contentWidth) end
    if self.questId and self:IsShown() then
        local ok, err = pcall(self.Render, self, self.questId)
        if not ok then QCT.Log:Add("window", "改宽后重排失败:", tostring(err)) end
    end
    return newWidth
end

--------------------------------------------------------------------------------
-- 创建
--------------------------------------------------------------------------------

local function MakeBackdrop(frame)
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
        frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
        return
    end
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    background:SetAllPoints()
    background:SetVertexColor(0.04, 0.04, 0.05, 0.96)
end

function W:Create()
    if self.frame then return self.frame end

    self:ResolveWidth()

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Frame", WINDOW_NAME, UIParent, template)
    frame:SetSize(width, HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        W.userMoved = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    MakeBackdrop(frame)
    frame:Hide()

    self.frame = frame

    -- 标题栏（可拖动）
    local title = frame:CreateFontString(nil, "OVERLAY")
    local path, size, flags = GetFont()
    title:SetFont(path, size + 2, flags)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
    title:SetJustifyH("LEFT")
    title:SetTextColor(1, 0.82, 0.2)
    self.title = title

    -- 关闭按钮（自绘，避免模板缺失）
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    local closeBg = close:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    closeBg:SetVertexColor(0.35, 0.1, 0.1, 0.9)
    local closeText = close:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(path, size + 3, flags)
    closeText:SetPoint("CENTER")
    closeText:SetText("×")
    closeText:SetTextColor(1, 0.9, 0.9)
    close:SetScript("OnClick", function() W:Close() end)
    close:SetScript("OnEnter", function()
        closeBg:SetVertexColor(0.65, 0.15, 0.15, 1)
    end)
    close:SetScript("OnLeave", function()
        closeBg:SetVertexColor(0.35, 0.1, 0.1, 0.9)
    end)
    self.close = close

    -- 「显示已完成 / 隐藏已完成」切换按钮（右上，关闭键左边）
    local toggle = CreateFrame("Button", nil, frame)
    toggle:SetSize(104, 20)
    toggle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -9)
    local toggleBg = toggle:CreateTexture(nil, "BACKGROUND")
    toggleBg:SetAllPoints()
    toggleBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    toggleBg:SetVertexColor(0.16, 0.16, 0.2, 0.95)
    local toggleLabel = toggle:CreateFontString(nil, "OVERLAY")
    toggleLabel:SetFont(path, size - 1, flags)
    toggleLabel:SetPoint("CENTER")
    toggleLabel:SetTextColor(0.85, 0.85, 0.85)
    toggle:SetScript("OnClick", function() W:ToggleShowCompleted() end)
    toggle:SetScript("OnEnter", function()
        toggleBg:SetVertexColor(0.28, 0.28, 0.34, 1)
    end)
    toggle:SetScript("OnLeave", function()
        toggleBg:SetVertexColor(0.16, 0.16, 0.2, 0.95)
    end)
    self.completedToggle = toggle
    self.completedLabel = toggleLabel

    -- 分隔线
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.4, 0.4, 0.4, 0.8)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_HEIGHT + 4))
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TITLE_HEIGHT + 4))
    self.divider = divider

    -- 滚动区
    local scroll = CreateFrame("ScrollFrame", WINDOW_NAME .. "Scroll", frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_HEIGHT + 12))
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PAD + SCROLLBAR_WIDTH + 6), PAD)
    scroll:EnableMouse(true)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        W:Scroll(delta)
    end)
    scroll:SetScript("OnSizeChanged", function()
        W:UpdateScrollbar()
    end)
    self.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth, 100)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    -- 必须开启鼠标：否则行里的物品链接（|Hitem:...|h）收不到悬停事件
    content:EnableMouse(true)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta) W:Scroll(delta) end)
    scroll:SetScrollChild(content)
    self.content = content
    self:AttachItemLinks(content)

    -- 自绘滚动条
    local track = frame:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetVertexColor(0.15, 0.15, 0.15, 0.8)
    track:SetWidth(SCROLLBAR_WIDTH)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    self.track = track

    local thumb = CreateFrame("Button", nil, frame)
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetHeight(40)
    local thumbTexture = thumb:CreateTexture(nil, "ARTWORK")
    thumbTexture:SetAllPoints()
    thumbTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumbTexture:SetVertexColor(0.55, 0.55, 0.55, 0.95)
    thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    thumb:EnableMouse(true)
    thumb:SetScript("OnMouseDown", function(self)
        self.dragging = true
        local _, cursorY = GetCursorPosition()
        self.startCursorY = cursorY / UIParent:GetEffectiveScale()
        self.startScroll = scroll:GetVerticalScroll() or 0
    end)
    thumb:SetScript("OnMouseUp", function(self) self.dragging = false end)
    thumb:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / UIParent:GetEffectiveScale()
        local travel = math.max(1, (self.trackHeight or 100) - self:GetHeight())
        local ratio = (self.startCursorY - cursorY) / travel
        W:ScrollTo((self.startScroll or 0) + ratio * (self.maxScroll or 0))
    end)
    self.thumb = thumb

    self.rows = {}
    self.dividers = {}

    if UISpecialFrames then
        local found = false
        for _, name in ipairs(UISpecialFrames) do
            if name == WINDOW_NAME then found = true break end
        end
        if not found then table.insert(UISpecialFrames, WINDOW_NAME) end
    end

    return frame
end

--------------------------------------------------------------------------------
-- 行
--------------------------------------------------------------------------------

---行里的物品链接（|Hitem:...|h[name]|h）悬停时弹物品提示、点击打开物品。
---用 GameTooltip（和 RXPGuides 一样）而不是 ItemRefTooltip：本客户端实测这条路可用。
local function ItemTipFrame()
    return _G.GameTooltip or _G.ItemRefTooltip
end

local function IsForbidden(obj)
    if not obj or type(obj.IsForbidden) ~= "function" then return false end
    local ok, value = pcall(obj.IsForbidden, obj)
    return ok and value == true
end

function W:HideItemTip(owner)
    local tip = ItemTipFrame()
    if not tip then return end
    -- 只关自己开的那个，别把别人（任务提示）的 tooltip 关掉
    local sameOwner = true
    if owner and type(tip.GetOwner) == "function" then
        local ok, current = pcall(tip.GetOwner, tip)
        sameOwner = ok and current == owner
    end
    if sameOwner and not IsForbidden(tip) then
        tip:Hide()
    end
end

---注意两件事：
---1) 超链接脚本只能挂在 **Frame** 上，FontString 是 Region，没有脚本能力
---   （挂上去会报 "script type not supported by this object"）。
---2) Frame 默认**不处理超链接**，必须 SetHyperlinksEnabled(true)，
---   否则 OnHyperlinkEnter/Leave/Click 一次都不会触发。
---所以统一挂在内容帧上，由它接住内部所有行里的链接事件。
---@param frame table
function W:AttachItemLinks(frame)
    if not frame or frame.qctLinks then return end
    frame.qctLinks = true

    local hasHyperlinks = type(frame.SetHyperlinksEnabled) == "function"
    if hasHyperlinks then
        local ok, err = pcall(frame.SetHyperlinksEnabled, frame, true)
        if not ok then
            hasHyperlinks = false
            if QCT.Log then QCT.Log:Add("error", "SetHyperlinksEnabled 失败:", tostring(err)) end
        end
    end
    if QCT.Log then
        QCT.Log:Add("window", "超链接支持 | SetHyperlinksEnabled:", hasHyperlinks and "有" or "没有",
            "| GameTooltip:", type(_G.GameTooltip),
            "| ItemRefTooltip:", type(_G.ItemRefTooltip))
    end

    local function setScript(event, handler)
        -- 万一某个客户端连这个脚本类型都不支持，也不能让窗口渲染整体崩掉
        local ok, err = pcall(frame.SetScript, frame, event, handler)
        if not ok and QCT.Log then
            QCT.Log:Add("error", "挂超链接脚本失败:", event, "|", tostring(err))
        end
    end

    setScript("OnHyperlinkEnter", function(self, link)
        if QCT.Log then QCT.Log:Add("window", "超链接悬停:", tostring(link)) end
        local tip = ItemTipFrame()
        if not tip or IsForbidden(tip) or not link then return end
        tip:SetOwner(self, "ANCHOR_CURSOR")
        tip:SetHyperlink(link)
        -- 详情窗是 DIALOG 层，会压在物品提示上面（玩家反馈「任务描述遮挡了物品信息」，
        -- 表现是物品名和属性被窗口盖掉、只剩几个字露出来）。
        -- 这里把物品提示顶到 TOOLTIP 层最高级：物品信息永远可见，代价是它会盖住窗口一角。
        if type(tip.SetFrameStrata) == "function" then
            pcall(tip.SetFrameStrata, tip, "TOOLTIP")
        end
        if type(tip.SetFrameLevel) == "function" then
            pcall(tip.SetFrameLevel, tip, 900)
        end
        tip:Show()
    end)

    setScript("OnHyperlinkLeave", function(self)
        W:HideItemTip(self)
    end)

    setScript("OnHyperlinkClick", function(_, link, text, button)
        if type(SetItemRef) == "function" then
            pcall(SetItemRef, link, text, button)
        end
    end)
end

function W:AcquireRow(index)
    local row = self.rows[index]
    if row then return row end

    local path, size, flags = GetFont()
    row = self.content:CreateFontString(nil, "ARTWORK")
    row:SetFont(path, size, flags)
    row:SetJustifyH("LEFT")
    row:SetJustifyV("TOP")
    row:SetWordWrap(true)
    row:SetWidth(contentWidth)
    self.rows[index] = row
    return row
end

function W:ResetRows()
    for _, row in ipairs(self.rows) do
        row:SetText("")
        row:Hide()
    end
    for _, divider in ipairs(self.dividers or {}) do
        divider:Hide()
    end
    self.rowIndex = 0
    self.dividerIndex = 0
    self.cursorY = 0
end

---分隔线用贴图而不是字符：字符宽度随字体变，容易溢出换行
function W:PushDivider()
    self.dividerIndex = (self.dividerIndex or 0) + 1
    local divider = self.dividers[self.dividerIndex]
    if not divider then
        divider = self.content:CreateTexture(nil, "ARTWORK")
        divider:SetTexture("Interface\\Buttons\\WHITE8X8")
        divider:SetVertexColor(0.35, 0.35, 0.35, 0.85)
        divider:SetHeight(1)
        self.dividers[self.dividerIndex] = divider
    end

    divider:SetWidth(contentWidth)
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(self.cursorY + 4))
    divider:Show()

    self.cursorY = self.cursorY + 9
end

function W:Push(text, width, r, g, b)
    if not text or text == "" then return end

    self.rowIndex = self.rowIndex + 1
    local row = self:AcquireRow(self.rowIndex)

    row:SetWidth(width or contentWidth)
    row:SetTextColor(r or 1, g or 1, b or 1)
    row:SetText(text)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.cursorY)
    row:Show()

    local height = row:GetStringHeight() or 0
    if height <= 0 then height = 14 end
    self.cursorY = self.cursorY + height + LINE_GAP
end

function W:PushBlank(height)
    self.cursorY = self.cursorY + (height or BLOCK_GAP)
end

function W:PushWrapped(text, prefix, width, r, g, b)
    local lines = F.Wrap(text, prefix or "", width or contentWidth, self.content)
    for _, line in ipairs(lines) do
        self:Push(line, width or contentWidth, r, g, b)
    end
end

--------------------------------------------------------------------------------
-- 内容
--------------------------------------------------------------------------------

local function RewardLines(detail)
    local out = {}

    local parts = {}
    if detail.xp and detail.xp > 0 then
        local r, g, b = F.DifficultyColor(detail.level, detail.id)
        parts[#parts + 1] = F.Hex(r, g, b, F.Number(detail.xp) .. " " .. L["经验"])
    end
    if detail.money and detail.money > 0 then
        parts[#parts + 1] = F.Coins(detail.money)
    end
    if #parts > 0 then
        out[#out + 1] = table.concat(parts, "   ")
    end

    if detail.items and #detail.items > 0 then
        local texts = {}
        for _, item in ipairs(detail.items) do
            texts[#texts + 1] = item.text
        end
        out[#out + 1] = table.concat(texts, "   ")
    end

    for _, rep in ipairs(detail.reputations or {}) do
        local text = (rep.value > 0 and "+" or "") .. rep.value .. " " .. rep.faction
        out[#out + 1] = F.Hex(0.35, 0.55, 1, text)
    end

    return out
end

function W:RenderQuestBlock(detail, kind)
    if not detail then return end

    -- 分隔线（第一个块不画）
    if self.rowIndex and self.rowIndex > 0 then
        self:PushDivider()
    end

    -- 标题行：[前置] [31] 任务名   (精英 · 副本)   (进行中)
    local levelText = (detail.level and detail.level > 0) and ("[" .. detail.level .. "] ") or ""
    local r, g, b = F.DifficultyColor(detail.level, detail.id)
    local head = KindTag(kind) .. " " .. F.Hex(r, g, b, levelText .. detail.name)

    local tags = {}
    if detail.isDungeon then
        tags[#tags + 1] = F.Hex(1, 0.55, 0.25, detail.tagId == 81 and L["副本任务"] or L["团队副本"])
    elseif detail.tagText then
        tags[#tags + 1] = F.Hex(0.85, 0.75, 0.45, detail.tagText)
    end
    if #tags > 0 then
        head = head .. "  " .. F.Hex(0.5, 0.5, 0.5, "(") .. table.concat(tags, F.Hex(0.5, 0.5, 0.5, " · ")) .. F.Hex(0.5, 0.5, 0.5, ")")
    end
    head = head .. "   " .. F.Hex(0.5, 0.5, 0.5, "(") .. StateLine(detail.state) .. F.Hex(0.5, 0.5, 0.5, ")")

    self:Push(head)

    -- 在哪接 / 在哪交
    local startText
    if detail.startName then
        startText = detail.startName .. (detail.startZone and ("  ·  " .. detail.startZone) or "")
    elseif detail.startZone then
        startText = detail.startZone
    end
    if startText then
        self:Push(INDENT .. F.Hex(0.6, 0.6, 0.6, L["接取："]) .. F.Hex(0.85, 0.85, 0.85, startText))
    end

    local endText
    if detail.endName then
        endText = detail.endName .. (detail.endZone and ("  ·  " .. detail.endZone) or "")
    elseif detail.endZone then
        endText = detail.endZone
    end
    if endText then
        self:Push(INDENT .. F.Hex(0.6, 0.6, 0.6, L["交付："]) .. F.Hex(0.85, 0.85, 0.85, endText))
    end

    -- 任务详情
    local desc = detail.description or {}
    if #desc > 0 then
        self:Push(INDENT .. F.Hex(0.55, 0.55, 0.55, L["任务详情"]))
        local used = 0
        for _, paragraph in ipairs(desc) do
            if used >= MAX_DESC_LINES then break end
            for _, line in ipairs(F.Wrap(paragraph, INDENT .. "  ", contentWidth - 12, self.content)) do
                if used >= MAX_DESC_LINES then break end
                self:Push(line, contentWidth - 12, 0.86, 0.86, 0.86)
                used = used + 1
            end
        end
        if used >= MAX_DESC_LINES then
            self:Push(INDENT .. "  " .. F.Hex(0.5, 0.5, 0.5, L["…（描述较长，已截断）"]))
        end
    end

    -- 完成条件
    local objectives = detail.objectives or {}
    if #objectives > 0 then
        self:Push(INDENT .. F.Hex(0.55, 0.55, 0.55, L["完成条件"]))
        local used = 0
        for _, line in ipairs(objectives) do
            if used >= MAX_OBJECTIVE_LINES then break end
            for _, wrapped in ipairs(F.Wrap(line, INDENT .. "  - ", contentWidth - 12, self.content)) do
                if used >= MAX_OBJECTIVE_LINES then break end
                self:Push(wrapped, contentWidth - 12, 1, 0.95, 0.75)
                used = used + 1
            end
        end
        if used >= MAX_OBJECTIVE_LINES then
            self:Push(INDENT .. "  " .. F.Hex(0.5, 0.5, 0.5, L["…（条件较多，已截断）"]))
        end
    end

    -- 奖励
    local rewards = RewardLines(detail)
    if #rewards > 0 then
        self:Push(INDENT .. F.Hex(0.55, 0.55, 0.55, L["奖励"]))
        for _, line in ipairs(rewards) do
            self:PushWrapped(line, INDENT .. "  ", contentWidth - 12, 1, 1, 1)
        end
    end

    self:PushBlank(BLOCK_GAP)
end

--------------------------------------------------------------------------------
-- 渲染 / 显示
--------------------------------------------------------------------------------

function W:Render(questId)
    self:Create()
    self:ResetRows()

    local maxDepth = tonumber(QCT.db.chainDepthShift) or 30
    if maxDepth < 1 then maxDepth = 30 end
    local entries = D:BuildFullChain(questId, maxDepth)

    local rendered = 0
    local hiddenCompleted = 0
    local completedTotal = 0

    for _, entry in ipairs(entries) do
        local detail = D:GetQuestDetail(entry.id)
        if detail then
            -- 已完成的任务默认折叠起来，当前任务无论什么状态都显示
            local isCompleted = (detail.state == "completed")
            if isCompleted then completedTotal = completedTotal + 1 end

            if isCompleted and entry.kind ~= "current" and not self.showCompleted then
                hiddenCompleted = hiddenCompleted + 1
            else
                self:RenderQuestBlock(detail, entry.kind)
                rendered = rendered + 1
            end
        end
    end

    self.hiddenCompleted = hiddenCompleted
    self.completedCount = completedTotal

    if hiddenCompleted > 0 then
        self:PushDivider()
        self:Push(F.Hex(0.55, 0.55, 0.55,
            L.F("已隐藏 %d 个已完成的任务 · 点右上角「显示全部」展开", hiddenCompleted)))
    end

    if rendered == 0 then
        self:Push(F.Hex(1, 0.4, 0.4, L["没有取到任务数据（Questie 数据源可能未就绪）"]))
        self:PushBlank(20)
    end

    self.content:SetHeight(math.max(1, self.cursorY + 8))
    self.questId = questId

    local name = D:GetName(questId) or L.F("任务 %s", tostring(questId))
    local suffix
    if hiddenCompleted > 0 then
        suffix = L.F("（%d 环，已隐藏 %d 个已完成）", rendered, hiddenCompleted)
    else
        suffix = L.F("（%d 环）", rendered)
    end
    self.title:SetText(L.F("任务链详情 · %s", name) .. F.Hex(0.6, 0.6, 0.6, suffix))

    self:UpdateCompletedToggle()

    self.scroll:SetVerticalScroll(0)
    self:UpdateScrollbar()

    QCT.Log:Add("window", "渲染详情窗 | 任务:", questId, "| 显示环节:", rendered,
        "| 隐藏已完成:", hiddenCompleted, "| 展开全部:", self.showCompleted and "是" or "否")
end

---右上角「显示全部 / 隐藏已完成」按钮的状态
function W:UpdateCompletedToggle()
    local toggle = self.completedToggle
    if not toggle then return end

    -- 整条链里压根没有已完成的任务，按钮就不用出现
    if (self.completedCount or 0) == 0 then
        toggle:Hide()
        return
    end

    toggle:Show()
    if self.showCompleted then
        self.completedLabel:SetText(L["隐藏已完成"])
        self.completedLabel:SetTextColor(1, 0.82, 0.2)
    else
        self.completedLabel:SetText(L.F("显示全部 (%d)", self.hiddenCompleted or 0))
        self.completedLabel:SetTextColor(0.85, 0.85, 0.85)
    end
end

function W:ToggleShowCompleted()
    self.showCompleted = not self.showCompleted
    if self.questId then
        local ok, err = pcall(self.Render, self, self.questId)
        if not ok then QCT.Log:Add("window", "切换显示失败:", tostring(err)) end
    end
end

function W:Scroll(delta)
    local step = 40
    self:ScrollTo((self.scroll:GetVerticalScroll() or 0) - delta * step)
end

function W:ScrollTo(value)
    local maxScroll = self.maxScroll or 0
    if value < 0 then value = 0 end
    if value > maxScroll then value = maxScroll end
    self.scroll:SetVerticalScroll(value)
    self:UpdateScrollbar()
end

function W:UpdateScrollbar()
    if not (self.scroll and self.thumb and self.track) then return end

    local viewHeight = self.scroll:GetHeight() or 1
    local contentHeight = self.content:GetHeight() or 1
    local maxScroll = contentHeight - viewHeight
    if maxScroll < 0 then maxScroll = 0 end
    self.maxScroll = maxScroll

    local trackHeight = viewHeight
    self.thumb.trackHeight = trackHeight
    self.thumb.maxScroll = maxScroll

    if maxScroll <= 0 then
        self.thumb:Hide()
        return
    end

    self.thumb:Show()
    local thumbHeight = math.max(30, trackHeight * (viewHeight / contentHeight))
    self.thumb:SetHeight(thumbHeight)

    local scroll = self.scroll:GetVerticalScroll() or 0
    if scroll > maxScroll then scroll = maxScroll end
    local travel = trackHeight - thumbHeight
    local offset = (maxScroll > 0) and (scroll / maxScroll * travel) or 0
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPLEFT", self.track, "TOPLEFT", 0, -offset)
end

---按「哪里有空」摆窗口：优先光标右侧，右边放不下就翻到左边，上下贴边自动收回来。
---
---以前固定 CENTER（拖过之后一直停在原地），玩家反馈"永远从右下角冒出来"，
---在任务日志/地图边上把要看的任务挡得严严实实。
function W:PlaceWindow()
    local frame = self.frame
    if not frame then return end
    if self.userMoved then return end     -- 玩家自己拖过，就尊重他的位置

    local screenWidth = UIParent:GetWidth() or 1920
    local screenHeight = UIParent:GetHeight() or 1080
    local frameWidth = frame:GetWidth() or 0
    local frameHeight = frame:GetHeight() or 0
    -- 刚 /reload 后第一次开窗，尺寸可能还是 0（还没真正排版完），用配置值兜底
    if frameWidth <= 0 then frameWidth = width or 480 end
    if frameHeight <= 0 then frameHeight = HEIGHT or 500 end

    -- 屏幕居中（水平、垂直都居中）。玩家反馈：贴在光标旁会被挤到边上/偏上，
    -- 居中看着最稳，也不会一半在屏幕外。
    local x = (screenWidth - frameWidth) / 2
    local y = (screenHeight + frameHeight) / 2
    if y - frameHeight < 12 then y = 12 + frameHeight end
    if y > screenHeight - 12 then y = screenHeight - 12 end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    QCT.Log:Add("window", "摆放窗口（屏幕居中）:", string.format("%.0f,%.0f", x, y))
end

---Tab 页签：同一点位有多个任务时，在标题下方排一行，点一下就切过去
---@param index number
function W:CreateTab(index)
    local frame = self.frame
    local path, size, flags = GetFont()

    local tab = CreateFrame("Button", nil, frame)
    tab:SetSize(80, 18)

    local label = tab:CreateFontString(nil, "OVERLAY")
    label:SetFont(path, size - 1, flags)
    label:SetPoint("CENTER")
    label:SetJustifyH("CENTER")

    -- 当前页签下面画一条亮线，其它页签只有文字（不再用底色方块，看着不丑）
    local underline = tab:CreateTexture(nil, "ARTWORK")
    underline:SetTexture("Interface\\Buttons\\WHITE8X8")
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, -2)
    underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, -2)
    underline:SetVertexColor(1, 0.82, 0.2, 1)
    underline:Hide()

    tab.label = label
    tab.underline = underline
    return tab
end

---有页签时，把标题/分隔线/滚动区整体下移一点
function W:ShiftContent(hasTabs)
    if self.contentShifted == hasTabs then return end
    self.contentShifted = hasTabs

    local rows = self.tabRows or 1
    local offset = hasTabs and (14 + rows * 22) or 0
    if self.title then
        self.title:ClearAllPoints()
        self.title:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -10 - offset)
    end
    if self.divider then
        self.divider:ClearAllPoints()
        self.divider:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -(TITLE_HEIGHT + 4 + offset))
        self.divider:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -PAD, -(TITLE_HEIGHT + 4 + offset))
    end
    if self.scroll then
        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -(TITLE_HEIGHT + 12 + offset))
        self.scroll:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -(PAD + SCROLLBAR_WIDTH + 6), PAD)
    end
end

---设置页签列表（list[1] 是当前打开的）
function W:SetTabs(list, activeId)
    local frame = self.frame
    if not frame then return end
    self.tabList = list
    self.tabButtons = self.tabButtons or {}

    local count = type(list) == "table" and #list or 0
    if count < 2 then
        for _, button in ipairs(self.tabButtons) do button:Hide() end
        self:ShiftContent(false)
        return
    end

    local shown = math.min(count, 4)
    local frameWidth = frame:GetWidth() or width or 480
    local maxX = frameWidth - PAD
    local cursorX, cursorY = PAD, -9
    local rows = 1

    for index = 1, shown do
        local button = self.tabButtons[index] or self:CreateTab(index)
        self.tabButtons[index] = button

        local questId = list[index]
        local name = D:GetName(questId) or ("#" .. tostring(questId))
        button.label:SetText(name)

        -- 完整显示名字：宽度 = 文字宽度 + 内边距，不截断
        local textWidth = button.label:GetStringWidth() or 0
        local tabWidth = math.max(48, textWidth + 20)
        button:SetSize(tabWidth, 18)
        button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, -2)
        button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, -2)

        -- 一行放不下就换行
        if cursorX + tabWidth > maxX and cursorX > PAD then
            cursorX = PAD
            cursorY = cursorY - 22
            rows = rows + 1
        end

        local active = (questId == activeId)
        button.label:SetTextColor(active and 1 or 0.72, active and 0.85 or 0.72, active and 0.3 or 0.72)
        if active then button.underline:Show() else button.underline:Hide() end

        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", cursorX, cursorY)
        cursorX = cursorX + tabWidth + 10

        button:SetScript("OnClick", function()
            if questId ~= activeId then
                W:Open(questId, list)
            end
        end)
        button:SetScript("OnEnter", function()
            if questId ~= activeId then button.label:SetTextColor(1, 1, 1) end
        end)
        button:SetScript("OnLeave", function()
            if questId ~= activeId then button.label:SetTextColor(0.72, 0.72, 0.72) end
        end)
        button:Show()
    end

    for index = shown + 1, #self.tabButtons do
        self.tabButtons[index]:Hide()
    end

    self.tabRows = rows
    self:ShiftContent(true)
end

function W:Open(questId, tabList)
    if not questId then return end
    if not QCT.db.enabled then return end

    -- 每次打开都回到默认状态：已完成的先折叠
    self.showCompleted = false

    -- 分辨率可能换过、宽度也可能刚被改过，开窗前重新算一次
    self:Create()
    self:ResolveWidth()
    if self.frame then self.frame:SetSize(width, HEIGHT) end
    if self.content then self.content:SetWidth(contentWidth) end

    local ok, err = pcall(self.Render, self, questId)
    if not ok then
        QCT.Log:Add("window", "渲染出错:", tostring(err))
        if self.lastPrintedError ~= tostring(err) then
            self.lastPrintedError = tostring(err)
            QCT:Print(L.F("任务链窗口渲染出错：%s", tostring(err)))
        end
        return
    end

    self.frame:Show()
    pcall(self.SetTabs, self, tabList, questId)
    pcall(self.PlaceWindow, self)
    -- 排版要一帧才稳定，所以下一帧再按真实尺寸摆一次（否则首次开窗会偏）
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if W.frame and W.frame:IsShown() then pcall(W.PlaceWindow, W) end
        end)
    end

    -- 详情窗已经把同样的内容展开得更全了，行内面板就收起来，避免两份信息互相挡
    if QCT.Tooltip and QCT.Tooltip.Hide then
        pcall(QCT.Tooltip.Hide, QCT.Tooltip)
    end
end

function W:Close()
    -- 记一笔：万一窗口"莫名消失"，/qct trace 能看到是哪一次关的
    QCT.Log:Add("window", "Close() 被调用 | 当前任务:", tostring(self.questId),
        "| 来源:", self.fromMap and "地图" or "非地图")
    self:HideItemTip()
    if self.frame then self.frame:Hide() end
end

function W:IsShown()
    return self.frame ~= nil and self.frame:IsShown() == true
end

function W:Toggle(questId)
    if self:IsShown() then
        self:Close()
    else
        self:Open(questId)
    end
end
